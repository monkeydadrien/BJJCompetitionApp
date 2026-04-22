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
    for round_idx, round_el in enumerate(soup.select(".tournament-category__bracket"), 1):
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


# ---------------------------------------------------------------------------
# Tournament days (mat-schedule view)
# ---------------------------------------------------------------------------

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_tournament_days(tournament_id: int) -> list[dict]:
    """
    Return the list of tournament days for a tournament.

    Source: /tournaments/{tid}/schedule has `<a href="#day{did}">Friday Start Time: 09:30 AM</a>`
    anchors that point to `<div id="day{did}">...</div>` sections. We harvest those plus
    the mat count from any visible tournament_day link.
    """
    time.sleep(POLITE_DELAY)
    url = f"{COMPSYS_BASE}/tournaments/{tournament_id}/schedule"
    resp = httpx.get(url, headers=HEADERS, timeout=20, follow_redirects=True)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")

    days: list[dict] = []
    seen: set[int] = set()

    # Anchor labels: <a href="#day4674">Friday Start Time: 09:30 AM</a>
    for a in soup.select("a[href^='#day']"):
        href = a.get("href", "")
        m = re.match(r"^#day(\d+)$", href)
        if not m:
            continue
        day_id = int(m.group(1))
        if day_id in seen:
            continue
        seen.add(day_id)

        label = a.get_text(" ", strip=True)
        wd_m = re.match(
            r"^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b",
            label,
            re.IGNORECASE,
        )
        time_m = re.search(r"(\d{1,2}:\d{2}\s*(?:AM|PM))", label, re.IGNORECASE)

        days.append({
            "dayId": day_id,
            "tournamentId": tournament_id,
            "label": label,
            "weekday": wd_m.group(1) if wd_m else None,
            "startTime": time_m.group(1) if time_m else None,
        })

    # Stable order by day_id (smaller = earlier day)
    days.sort(key=lambda d: d["dayId"])
    return days


def _parse_tday_competitor(comp_el) -> dict:
    """Parse a competitor from the tournament_days match card (same structure as brackets)."""
    athlete_id_match = re.search(r"competitor-(\d+)", comp_el.get("id", ""))
    name_el = comp_el.select_one(".match-card__competitor-name")
    club_el = comp_el.select_one(".match-card__club-name")
    seed_el = comp_el.select_one(".match-card__competitor-n")

    name = name_el.get_text(strip=True) if name_el else ""
    if not name:
        placeholder = comp_el.get_text(" ", strip=True)
        return {"placeholder": placeholder or "TBD"}

    return {
        "athleteId": int(athlete_id_match.group(1)) if athlete_id_match else None,
        "name": name,
        "club": club_el.get_text(strip=True) if club_el else "",
        "seed": int(seed_el.get_text(strip=True)) if seed_el and seed_el.get_text(strip=True).isdigit() else None,
    }


def _parse_tday_page(soup) -> tuple[list[dict], int]:
    """
    Parse one tournament_days page into (mats, max_page).
    Returns a list of {matName, matches: [...]}.
    """
    mats: list[dict] = []
    for col in soup.select("li.sliding-columns__column"):
        header = col.select_one(".grid-column__header")
        mat_name = header.get_text(" ", strip=True) if header else ""
        ul = col.select_one("ul.tournament-day__mats")
        matches: list[dict] = []
        if ul:
            for li in ul.select(":scope > li"):
                when_el = li.select_one(".match-header__when")
                fight_el = li.select_one(".match-header__fight")
                phase_el = li.select_one(".match-header__phase")
                cat_el = li.select_one(".match-header__category-name")
                status_el = li.select_one(".match-header__fight-status")

                when_text = when_el.get_text(" ", strip=True) if when_el else ""
                # when text often looks like "09:30 AM: FIGHT 1" — strip trailing "FIGHT N"
                when_text = re.sub(r"\s*FIGHT\s+\d+\s*$", "", when_text, flags=re.IGNORECASE).rstrip(": ").strip()

                fight_num = None
                if fight_el:
                    fm = re.search(r"FIGHT\s+(\d+)", fight_el.get_text(), re.IGNORECASE)
                    if fm:
                        fight_num = int(fm.group(1))

                phase = phase_el.get_text(" ", strip=True).strip("()") if phase_el else None
                category = cat_el.get_text(" ", strip=True) if cat_el else ""

                # Status: the class includes fa-circle/fa-check/fa-play (etc). We surface the icon class.
                status = None
                if status_el:
                    classes = status_el.get("class", [])
                    for c in classes:
                        if c.startswith("fa-") and c != "fa-circle":
                            status = c
                            break
                    if not status and "fa-circle" in classes:
                        status = "fa-circle"

                competitors = [_parse_tday_competitor(c) for c in li.select(".match-card__competitor")]

                matches.append({
                    "fight": fight_num,
                    "when": when_text or None,
                    "phase": phase,
                    "category": category or None,
                    "status": status,
                    "competitors": competitors,
                })

        mats.append({"matName": mat_name, "matches": matches})

    # Determine max page from pagination links
    max_page = 1
    for a in soup.select("a[href*='page=']"):
        m = re.search(r"page=(\d+)", a.get("href", ""))
        if m:
            max_page = max(max_page, int(m.group(1)))

    return mats, max_page


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def _fetch_tday_page(tournament_id: int, day_id: int, page: int) -> tuple[list[dict], int]:
    time.sleep(POLITE_DELAY)
    url = f"{COMPSYS_BASE}/tournaments/{tournament_id}/tournament_days/{day_id}"
    params = {"page": page} if page > 1 else None
    resp = httpx.get(url, headers=HEADERS, params=params, timeout=25, follow_redirects=True)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")
    return _parse_tday_page(soup)


def fetch_tournament_day(tournament_id: int, day_id: int) -> dict:
    """
    Fetch every mat column across all pages for a given day.
    Returns {tournamentId, dayId, mats: [{matName, matches: [...]}, ...]}.

    Pages on compsystem show 4 mats each; we walk ?page=1, ?page=2, ... until we've
    read the max page advertised by the pagination links.
    """
    first_mats, max_page = _fetch_tday_page(tournament_id, day_id, 1)
    all_mats = list(first_mats)

    page = 2
    while page <= max_page:
        try:
            mats, next_max = _fetch_tday_page(tournament_id, day_id, page)
        except Exception:
            page += 1
            continue
        if not mats:
            break
        all_mats.extend(mats)
        # Pagination link set may widen as we advance through pages
        if next_max > max_page:
            max_page = next_max
        page += 1

    return {
        "tournamentId": tournament_id,
        "dayId": day_id,
        "mats": all_mats,
    }


# ---------------------------------------------------------------------------
# Full tournament scan (used by the /schedule endpoint)
# ---------------------------------------------------------------------------

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
