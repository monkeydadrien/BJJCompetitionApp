#!/usr/bin/env python3
"""
One-off historical scrape of bjjcompsystem.com to build a registry of athletes
(stable athleteIds + names + teams) over the last ~12 months.

Usage:
  python backfill_athletes.py                       # Default: 12 months back
  python backfill_athletes.py --months 6
  python backfill_athletes.py --start-id 3174       # Override autodetect
  python backfill_athletes.py --max-tournaments 50
  python backfill_athletes.py --fresh               # Ignore checkpoint
  python backfill_athletes.py --dry-run             # No output file

Output:
  ../athletes.json (repo root)                      # Publishable registry
  .athletes_backfill_state.json                     # Resumable checkpoint
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import httpx
from bs4 import BeautifulSoup
from concurrent.futures import ThreadPoolExecutor, as_completed

import compsystem_client as _cs
# Speed up bracket fetching for the one-off backfill scrape.
# 0.3s is still polite; the semaphore(3) limits concurrency anyway.
_cs.POLITE_DELAY = 0.3

from compsystem_client import (
    COMPSYS_BASE,
    HEADERS,
    _fetch_bracket_safe,
    _parse_competitor,
    fetch_tournaments,  # used both for START_ID and to build the upcoming-skip set
)
POLITE_DELAY = _cs.POLITE_DELAY

REPO_ROOT = Path(__file__).parent.parent
OUTPUT_FILE = REPO_ROOT / "athletes.json"
STATE_FILE = Path(__file__).parent / ".athletes_backfill_state.json"

DEFAULT_MONTHS = 12
DEFAULT_MAX_TOURNAMENTS = 200
ID_FLOOR_OFFSET = 1500
DATE_GRACE_DAYS = 30         # allow ~1 extra month of slack past --months
CHECKPOINT_INTERVAL = 5


# ---------------------------------------------------------------------------
# Date parsing helpers
# ---------------------------------------------------------------------------

# bjjcompsystem renders dates like "Sat 03/14/2026 11:30" for completed events,
# and just "Sat 11:30" for upcoming. We extract the MM/DD/YYYY when present.
_DATE_RE = re.compile(r"(\d{1,2})/(\d{1,2})/(\d{4})")


def _parse_when_date(text: str) -> Optional[date]:
    m = _DATE_RE.search(text or "")
    if not m:
        return None
    try:
        mm, dd, yyyy = int(m.group(1)), int(m.group(2)), int(m.group(3))
        return date(yyyy, mm, dd)
    except ValueError:
        return None


def _probe_tournament_date(tournament_id: int, sample_category_id: int) -> Optional[date]:
    """Fetch one bracket and scan its header `when` strings for an earliest dateable value."""
    time.sleep(POLITE_DELAY)
    url = f"{COMPSYS_BASE}/tournaments/{tournament_id}/categories/{sample_category_id}"
    try:
        resp = httpx.get(url, headers=HEADERS, timeout=20, follow_redirects=True)
        resp.raise_for_status()
    except Exception:
        return None
    soup = BeautifulSoup(resp.text, "lxml")
    earliest: Optional[date] = None
    for el in soup.select(".bracket-match-header__when"):
        d = _parse_when_date(el.get_text(strip=True))
        if d and (earliest is None or d < earliest):
            earliest = d
    return earliest


# ---------------------------------------------------------------------------
# Tournament discovery
# ---------------------------------------------------------------------------

def _get_categories_safe(tournament_id: int, gender_id: int) -> list[dict]:
    """
    Fast one-shot probe — no retry, returns [] on any HTTP/network error.

    We intentionally bypass `fetch_categories` (which has @retry with exponential
    backoff) because gap tournament IDs would waste 6+ seconds per ID exhausting
    three retry attempts before we can move on.
    """
    url = f"{COMPSYS_BASE}/tournaments/{tournament_id}/categories?gender_id={gender_id}"
    try:
        time.sleep(POLITE_DELAY)
        resp = httpx.get(url, headers=HEADERS, timeout=10, follow_redirects=True)
        resp.raise_for_status()
    except Exception:
        return []
    soup = BeautifulSoup(resp.text, "lxml")
    categories = []
    for li in soup.select("li.public-categories__category"):
        link = li.select_one("a[href*='/categories/']")
        if not link:
            continue
        href = link.get("href", "")
        m = re.search(r"/categories/(\d+)", href)
        if not m:
            continue
        cid = int(m.group(1))
        card = li.select_one(".category-card")
        age_el = card.select_one(".category-card__age-division") if card else None
        belt_el = card.select_one(".category-card__belt-label .category-card__label-text") if card else None
        weight_el = card.select_one(".category-card__weight-label .category-card__label-text") if card else None
        age = age_el.get_text(strip=True) if age_el else ""
        belt = belt_el.get_text(strip=True) if belt_el else ""
        weight = weight_el.get_text(strip=True) if weight_el else ""
        label = " / ".join(filter(None, [age, belt, weight]))
        categories.append({
            "id": cid,
            "tournamentId": tournament_id,
            "gender": "Male" if gender_id == 1 else "Female",
            "label": label,
        })
    return categories


def _autodetect_start_id() -> int:
    """Highest tournament id from the upcoming dropdown."""
    tournaments = fetch_tournaments()
    if not tournaments:
        raise RuntimeError("Could not fetch tournament list from bjjcompsystem")
    return max(t["id"] for t in tournaments)


# ---------------------------------------------------------------------------
# Checkpointing
# ---------------------------------------------------------------------------

def _load_state(resume: bool) -> dict:
    if not resume or not STATE_FILE.exists():
        return {
            "startedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "startId": None,
            "lastProcessedId": None,
            "skippedIds": [],
            "athletes": {},   # str(id) -> record
            "scannedTournaments": [],  # [{id, date}]
            "oldestTournamentDate": None,
        }
    with STATE_FILE.open() as f:
        state = json.load(f)
    print(f"  Resuming: {len(state['athletes'])} athletes, "
          f"last processed tournament id={state['lastProcessedId']}")
    return state


def _save_state(state: dict) -> None:
    tmp = STATE_FILE.with_suffix(".tmp")
    with tmp.open("w") as f:
        json.dump(state, f)
    tmp.replace(STATE_FILE)


# ---------------------------------------------------------------------------
# Per-tournament extraction
# ---------------------------------------------------------------------------

def _extract_athletes_from_tournament(
    tournament_id: int,
    categories: list[dict],
) -> list[dict]:
    """
    Fetch all brackets for the given categories and return a flat list of
    athlete observations: [{id, name, team}].
    """
    observations: list[dict] = []
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = {
            executor.submit(_fetch_bracket_safe, tournament_id, cat["id"]): cat
            for cat in categories
        }
        for future in as_completed(futures):
            bracket = future.result()
            if not bracket:
                continue
            for match in bracket.get("matches", []):
                for comp in match.get("competitors", []):
                    aid = comp.get("athleteId")
                    name = comp.get("name")
                    if aid is None or not name:
                        continue
                    observations.append({
                        "id": int(aid),
                        "name": name,
                        "team": comp.get("club") or "",
                    })
    return observations


# ---------------------------------------------------------------------------
# Main backfill
# ---------------------------------------------------------------------------

def backfill(
    start_id: Optional[int],
    months: int,
    max_tournaments: int,
    min_categories: int,
    resume: bool,
    dry_run: bool,
) -> None:
    state = _load_state(resume)

    if start_id is None:
        if state.get("startId"):
            start_id = state["startId"]
            print(f"  Using start id from checkpoint: {start_id}")
        else:
            print("Autodetecting start id from bjjcompsystem dropdown...")
            start_id = _autodetect_start_id()
            print(f"  START_ID = {start_id}")

    state["startId"] = start_id
    id_floor = max(1, start_id - ID_FLOOR_OFFSET)
    cutoff_date = date.today() - timedelta(days=30 * months + DATE_GRACE_DAYS)
    print(f"  Cutoff date: {cutoff_date.isoformat()} (stop if tournament is older)")
    print(f"  ID floor: {id_floor}, max tournaments: {max_tournaments}"
          + (f", min categories: {min_categories}" if min_categories > 0 else ""))

    # Fetch upcoming IDs so we can skip them without probing their brackets.
    # The dropdown only has ~10-20 entries; this is a one-time fast call.
    try:
        upcoming_raw = fetch_tournaments()
        upcoming_ids: set[int] = {t["id"] for t in upcoming_raw}
        upcoming_min = min(upcoming_ids) if upcoming_ids else start_id
        print(f"  Upcoming tournaments to skip: {len(upcoming_ids)} "
              f"(IDs {upcoming_min}–{max(upcoming_ids) if upcoming_ids else start_id})")
    except Exception:
        upcoming_ids = set()
        upcoming_min = start_id
    print()
    processed_count = len(state["scannedTournaments"])
    skipped_count = len(state["skippedIds"])
    oldest_seen: Optional[date] = (
        date.fromisoformat(state["oldestTournamentDate"])
        if state.get("oldestTournamentDate") else None
    )

    # Jump below the upcoming cluster to avoid probing pre-registered future events.
    if state["lastProcessedId"]:
        start_iter_id = state["lastProcessedId"] - 1
    elif upcoming_ids:
        start_iter_id = upcoming_min - 1
        print(f"  Jumping to id={start_iter_id} (below upcoming cluster)")
    else:
        start_iter_id = start_id

    current = start_iter_id
    while current >= id_floor:
        if processed_count >= max_tournaments:
            print(f"\nHit max tournaments cap ({max_tournaments}). Stopping.")
            break

        # Skip known upcoming tournaments — no need to probe their brackets.
        if current in upcoming_ids:
            skipped_count += 1
            current -= 1
            continue

        # Probe: fetch categories for both genders
        try:
            cats_m = _get_categories_safe(current, 1)
            cats_f = _get_categories_safe(current, 2)
        except Exception as e:
            print(f"  [{current}] probe error: {e}; skipping")
            state["skippedIds"].append(current)
            current -= 1
            continue

        categories = cats_m + cats_f
        if not categories:
            state["skippedIds"].append(current)
            skipped_count += 1
            current -= 1
            continue

        # Skip small regional events if --min-categories set
        if min_categories > 0 and len(categories) < min_categories:
            skipped_count += 1
            current -= 1
            continue

        # Date probe using the first category
        sample_cid = categories[0]["id"]
        t_date = _probe_tournament_date(current, sample_cid)
        date_str = t_date.isoformat() if t_date else "unknown"

        processed_count += 1
        print(f"  [{processed_count}/{max_tournaments}] tid={current} date={date_str} "
              f"categories={len(categories)}")

        # Stop condition: dateable and older than cutoff
        if t_date and t_date < cutoff_date:
            print(f"  Reached cutoff date ({t_date} < {cutoff_date}). Stopping.")
            break

        # Extract athletes
        observations = _extract_athletes_from_tournament(current, categories)
        new_count = 0
        for obs in observations:
            key = str(obs["id"])
            if key in state["athletes"]:
                continue
            state["athletes"][key] = {
                "id": obs["id"],
                "name": obs["name"],
                "team": obs["team"],
                "lastSeenTournamentId": current,
                "lastSeenDate": date_str if t_date else None,
            }
            new_count += 1
        print(f"    +{new_count} new athletes (total: {len(state['athletes'])})")

        state["scannedTournaments"].append({"id": current, "date": date_str if t_date else None})
        state["lastProcessedId"] = current
        if t_date and (oldest_seen is None or t_date < oldest_seen):
            oldest_seen = t_date
            state["oldestTournamentDate"] = oldest_seen.isoformat()

        if processed_count % CHECKPOINT_INTERVAL == 0:
            _save_state(state)

        current -= 1
        time.sleep(0.5)  # gentle inter-tournament throttle

    _save_state(state)
    print()
    print(f"Done. Processed {processed_count} tournaments, skipped {skipped_count} empty IDs.")
    print(f"Unique athletes: {len(state['athletes'])}")
    if oldest_seen:
        print(f"Oldest tournament date: {oldest_seen.isoformat()}")

    if dry_run:
        print("\n[dry-run] Skipping athletes.json write.")
        return

    # Sort athletes: most recent first (by lastSeenDate desc, then name asc)
    records = list(state["athletes"].values())
    records.sort(key=lambda a: (
        a.get("lastSeenDate") or "0000-00-00",
        a.get("name") or "",
    ))
    records.sort(key=lambda a: a.get("lastSeenDate") or "0000-00-00", reverse=True)

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "oldestTournamentDate": oldest_seen.isoformat() if oldest_seen else None,
        "count": len(records),
        "athletes": records,
    }
    with OUTPUT_FILE.open("w") as f:
        json.dump(payload, f, ensure_ascii=False)
    size_kb = OUTPUT_FILE.stat().st_size / 1024
    print(f"\nWrote {OUTPUT_FILE} ({size_kb:.1f} KB)")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--start-id", type=int, default=None, help="Override starting tournament id")
    parser.add_argument("--months", type=int, default=DEFAULT_MONTHS, help="Months of history (default 12)")
    parser.add_argument("--max-tournaments", type=int, default=DEFAULT_MAX_TOURNAMENTS,
                        help=f"Safety cap (default {DEFAULT_MAX_TOURNAMENTS})")
    parser.add_argument("--fresh", action="store_true", help="Ignore checkpoint; start over")
    parser.add_argument("--dry-run", action="store_true", help="Do not write athletes.json")
    parser.add_argument("--min-categories", type=int, default=0,
                        help="Skip tournaments with fewer than N total categories (0 = no filter). "
                             "Use 150+ to target only large IBJJF events (Worlds, Pan-Ams, Nationals).")
    args = parser.parse_args()

    resume = not args.fresh

    try:
        backfill(
            start_id=args.start_id,
            months=args.months,
            max_tournaments=args.max_tournaments,
            min_categories=args.min_categories,
            resume=resume,
            dry_run=args.dry_run,
        )
    except KeyboardInterrupt:
        print("\n\nInterrupted. Checkpoint saved — re-run with --resume (default) to continue.")
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
