"""
Client for scraping bracket data from bjjcompsystem.com.

Sources (all server-rendered HTML — no JS required):
  - Tournament list:  https://www.bjjcompsystem.com/tournaments
  - Categories index: https://www.bjjcompsystem.com/tournaments/{tid}/categories?gender_id=1
  - Bracket page:     https://www.bjjcompsystem.com/tournaments/{tid}/categories/{cid}

NOTE: robots.txt disallows all crawling. We keep requests polite:
  - Identifying User-Agent
  - ~1 req/sec delay
  - Only fetch brackets on explicit user action (via proxy cache)
"""

from __future__ import annotations

import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional

import httpx
from bs4 import BeautifulSoup
from tenacity import retry, stop_after_attempt, wait_exponential

# Limit concurrent outbound requests to compsystem to be polite
_semaphore = threading.Semaphore(3)

COMPSYS_BASE = "https://www.bjjcompsystem.com"
POLITE_DELAY = 1.0

HEADERS = {
    "User-Agent": (
        "BJJCompanionApp/1.0 (personal competition prep tool; "
        "contact: see github.com/adrienibarra/bjj-companion)"
    ),
    "Accept": "text/html,application/xhtml+xml",
    "Accept-Language": "en-US,en;q=0.9",
}


# ---------------------------------------------------------------------------
# Data models (simple dicts — serialised by the proxy)
# ---------------------------------------------------------------------------

# Tournament: {id, name, date_label, location}
# Category:   {id, tournament_id, gender, label}  (label = "Adult / Black / Heavy")
# Competitor: {athleteId, name, club, seed} or {placeholder}
# Match:      {fight, mat, when, round, slot, competitors: [...], nextFight}
# Bracket:    {tournamentId, categoryId, label, matches: [...]}


# ---------------------------------------------------------------------------
# Tournaments list
# ---------------------------------------------------------------------------

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_tournaments() -> list[dict]:
    """Return all tournaments from the listing page select dropdown."""
    resp = httpx.get(f"{COMPSYS_BASE}/tournaments", headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")

    tournaments = []
    select = soup.select_one("select#tournament_id")
    if not select:
        return tournaments

    for option in select.select("option"):
        value = option.get("value", "").strip()
        name = option.get_text(strip=True)
        if value and name:
            tournaments.append({"id": int(value), "name": name})

    return tournaments


# ---------------------------------------------------------------------------
# Categories (brackets) for a tournament
# ---------------------------------------------------------------------------

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_categories(tournament_id: int, gender_id: int = 1) -> list[dict]:
    """
    Return categories for a tournament filtered by gender.
    gender_id: 1 = Male, 2 = Female
    """
    time.sleep(POLITE_DELAY)
    url = f"{COMPSYS_BASE}/tournaments/{tournament_id}/categories?gender_id={gender_id}"
    resp = httpx.get(url, headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
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

        # Parse structured label from card elements
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


# ---------------------------------------------------------------------------
# Bracket (match tree)
# ---------------------------------------------------------------------------

def _parse_competitor(comp_el) -> dict:
    """
    Parse a .match-card__competitor element into a competitor dict.
    Handles both real athletes and placeholder slots ("Winner of Fight N").
    """
    athlete_id_match = re.search(r'competitor-(\d+)', comp_el.get("id", ""))
    name_el = comp_el.select_one(".match-card__competitor-name")
    club_el = comp_el.select_one(".match-card__club-name")
    seed_el = comp_el.select_one(".match-card__competitor-n")

    name = name_el.get_text(strip=True) if name_el else ""
    if not name:
        # Unresolved slot — show placeholder text from the whole element
        placeholder = comp_el.get_text(" ", strip=True)
        return {"placeholder": placeholder or "TBD"}

    return {
        "athleteId": int(athlete_id_match.group(1)) if athlete_id_match else None,
        "name": name,
        "club": club_el.get_text(strip=True) if club_el else "",
        "seed": int(seed_el.get_text(strip=True)) if seed_el and seed_el.get_text(strip=True).isdigit() else None,
    }


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_bracket(tournament_id: int, category_id: int) -> dict:
    """
    Fetch and parse the bracket tree for a specific category.
    Returns a bracket dict with matches list.
    """
    time.sleep(POLITE_DELAY)
    url = f"{COMPSYS_BASE}/tournaments/{tournament_id}/categories/{category_id}"
    resp = httpx.get(url, headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")

    # Category label from page heading
    heading = soup.select_one("h2, h3, .tournament-category__name")
    label = heading.get_text(strip=True) if heading else ""

    matches = []
    for round_idx, round_el in enumerate(soup.select("[class*='tournament-category__bracket']"), 1):
        for match_el in round_el.select(".tournament-category__match"):
            # Fight number and mat
            header = match_el.select_one(".bracket-match-header__fight")
            fight_num = None
            if header:
                fight_match = re.search(r"FIGHT\s+(\d+)", header.get_text(), re.IGNORECASE)
                if fight_match:
                    fight_num = int(fight_match.group(1))

            # Mat: text inside __where EXCLUDING the __fight span
            mat_el = match_el.select_one(".bracket-match-header__where")
            mat = ""
            if mat_el:
                fight_span = mat_el.select_one(".bracket-match-header__fight")
                if fight_span:
                    fight_span.extract()
                mat = mat_el.get_text(strip=True)

            when_el = match_el.select_one(".bracket-match-header__when")

            # Slot id
            slot = match_el.get("id", "")

            # Competitors: two .match-card__competitor divs inside the match card
            competitors = []
            for comp_el in match_el.select(".match-card__competitor"):
                competitors.append(_parse_competitor(comp_el))

            # Next fight pointer from placeholder text "Winner of Fight N"
            next_fight = None
            for text in match_el.stripped_strings:
                nf = re.search(r"Winner of Fight\s+(\d+)", text, re.IGNORECASE)
                if nf:
                    next_fight = int(nf.group(1))
                    break

            matches.append({
                "fight": fight_num,
                "mat": mat or None,
                "when": when_el.get_text(strip=True) if when_el else None,
                "round": round_idx,
                "slot": slot,
                "competitors": competitors,
                "nextFight": next_fight,
            })

    return {
        "tournamentId": tournament_id,
        "categoryId": category_id,
        "label": label,
        "matches": matches,
    }


# ---------------------------------------------------------------------------
# Full tournament scan (used by the /schedule endpoint)
# ---------------------------------------------------------------------------

def _fetch_bracket_safe(tournament_id: int, category_id: int) -> dict | None:
    """Fetch a bracket with semaphore-controlled concurrency. Returns None on failure."""
    with _semaphore:
        try:
            return fetch_bracket(tournament_id, category_id)
        except Exception:
            return None


def fetch_all_tournament_matches(tournament_id: int) -> list[dict]:
    """
    Fetch ALL matches across ALL categories for a tournament (both genders).
    Each returned match dict includes categoryLabel and categoryId.

    This is the expensive operation — the proxy caches it for SCHEDULE_TTL seconds.
    Name filtering is done per-request on top of this cached result.
    """
    # Collect categories for both genders
    categories: list[dict] = []
    for gender_id in (1, 2):
        try:
            cats = fetch_categories(tournament_id, gender_id)
            categories.extend(cats)
        except Exception:
            pass  # if one gender fails, still try the other

    if not categories:
        return []

    all_matches: list[dict] = []

    # Fetch all brackets concurrently, semaphore limits to 3 in-flight at once
    with ThreadPoolExecutor(max_workers=5) as executor:
        future_to_cat = {
            executor.submit(_fetch_bracket_safe, tournament_id, cat["id"]): cat
            for cat in categories
        }
        for future in as_completed(future_to_cat):
            cat = future_to_cat[future]
            bracket = future.result()
            if not bracket:
                continue
            for match in bracket.get("matches", []):
                all_matches.append({
                    **match,
                    "categoryLabel": cat.get("label", ""),
                    "categoryId":    cat["id"],
                    "tournamentId":  tournament_id,
                })

    return all_matches
