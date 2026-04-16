#!/usr/bin/env python3
"""
Build athletes.json from past Texas IBJJF event registrations.
Much faster than bjjcompsystem scraping and directly targets the athletes
your team competes against at local/regional events.

Usage:
  python build_texas_athletes.py
"""
from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path

from ibjjf_client import (
    IBJJF_BASE, HEADERS, IBJJFDB_BASE,
    _make_client, fetch_registrations,
)

REPO_ROOT = Path(__file__).parent.parent
OUTPUT_FILE = REPO_ROOT / "athletes.json"

TEXAS_KEYWORDS = ["houston", "texas", "dallas", "san antonio", "austin"]


def fetch_texas_events() -> list[dict]:
    client = _make_client()
    resp = client.get(
        f"{IBJJF_BASE}/api/v1/events/calendar.json",
        headers={
            **HEADERS,
            "Referer": f"{IBJJF_BASE}/events/calendar",
            "X-Requested-With": "XMLHttpRequest",
            "Accept": "application/json",
        },
    )
    resp.raise_for_status()
    events = resp.json().get("infosite_events", [])

    texas = []
    for e in events:
        name = e.get("name", "").lower()
        city = e.get("city", "").lower()
        if any(k in name or k in city for k in TEXAS_KEYWORDS):
            texas.append(e)

    return texas


def main() -> None:
    print("Fetching Texas IBJJF events...")
    texas_events = fetch_texas_events()
    finished = [e for e in texas_events if e.get("status") == "finished"]
    print(f"  Found {len(texas_events)} Texas events total, {len(finished)} completed")
    print()

    # Deduplicate athletes by name+team (no stable ID from IBJJF)
    seen: dict[str, dict] = {}   # key: "name|team" → record
    sequential_id = 1

    for i, event in enumerate(finished, 1):
        name = event.get("name", "?")
        event_id = event.get("id")
        print(f"  [{i}/{len(finished)}] {name[:60]} (id={event_id})")

        try:
            divisions = fetch_registrations(event_id)
        except Exception as e:
            print(f"    WARN: {e}")
            continue

        new_count = 0
        for div in divisions:
            for athlete in div.athletes:
                key = f"{athlete.name.strip().lower()}|{(athlete.team or '').strip().lower()}"
                if key not in seen:
                    seen[key] = {
                        "id": sequential_id,
                        "name": athlete.name.strip(),
                        "team": (athlete.team or "").strip(),
                        "lastSeenDate": None,
                        "lastSeenTournamentId": event_id,
                    }
                    sequential_id += 1
                    new_count += 1

        print(f"    +{new_count} new athletes (total: {len(seen)})")

    records = list(seen.values())
    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "oldestTournamentDate": None,
        "count": len(records),
        "athletes": records,
    }
    with OUTPUT_FILE.open("w") as f:
        json.dump(payload, f, ensure_ascii=False)
    size_kb = OUTPUT_FILE.stat().st_size / 1024
    print(f"\nWrote {OUTPUT_FILE} ({size_kb:.1f} KB, {len(records)} athletes)")


if __name__ == "__main__":
    main()
