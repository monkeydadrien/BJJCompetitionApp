#!/usr/bin/env python3
"""
Rankings scraper — builds athletes.json from IBJJF ranking pages.

Usage:
  python scrape_rankings.py                # Scrape all standard combos
  python scrape_rankings.py --quick        # Adult belts only (faster)
  python scrape_rankings.py --max-pages 5  # Limit pages per combo (testing)

Output:  athletes.json (sibling to events.json, published via GitHub Pages)
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from bs4 import BeautifulSoup
from tenacity import retry, stop_after_attempt, wait_exponential

OUTPUT_FILE = Path(__file__).parent.parent / "athletes.json"

IBJJF_BASE = "https://ibjjf.com"
RANKING_YEAR = 2026
POLITE_DELAY = 1.0

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/123.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
}

# Standard combos to scrape
ADULT_BELTS = ["black", "brown", "purple", "blue", "white"]
MASTER_BELTS = ["black", "brown", "purple", "blue", "white"]
GENDERS = ["male", "female"]
MASTER_DIVS = ["master1", "master2", "master3", "master4", "master5", "master6", "master7"]

QUICK_COMBOS = [
    (belt, gender, "adult")
    for belt in ADULT_BELTS
    for gender in GENDERS
]

FULL_COMBOS = QUICK_COMBOS + [
    (belt, gender, age)
    for age in MASTER_DIVS
    for belt in MASTER_BELTS
    for gender in GENDERS
]


# ---------------------------------------------------------------------------
# Scraping functions
# ---------------------------------------------------------------------------

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_ranking_page(
    client: httpx.Client,
    belt: str,
    gender: str,
    age_division: str,
    page: int,
) -> tuple[list[dict], bool]:
    """Fetch one page. Returns (athletes, has_next_page)."""
    time.sleep(POLITE_DELAY)
    url = (
        f"{IBJJF_BASE}/{RANKING_YEAR}-athletes-ranking"
        f"?filters[age_division]={age_division}"
        f"&filters[belt]={belt}"
        f"&filters[gender]={gender}"
        f"&filters[s]=ranking-geral-gi"
        f"&filters[limit]=10"
        f"&page={page}"
    )
    resp = client.get(url)
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")

    athletes: list[dict] = []
    desktop_div = soup.find("div", class_="d-lg-flex")
    if not desktop_div:
        return [], False

    table = desktop_div.find("table")
    if not table:
        return [], False

    import re

    for tr in table.find_all("tr"):
        name_td = tr.find("td", class_="name-academy")
        if not name_td:
            continue

        pos_td = tr.find("td", class_="position")
        pts_td = tr.find("td", class_="pontuation")
        photo_td = tr.find("td", class_="photo")

        name_div = name_td.find("div", class_="name")
        acad_div = name_td.find("div", class_="academy")

        name_a = name_div.find("a") if name_div else None
        athlete_name = name_a.get_text(strip=True) if name_a else (name_div.get_text(strip=True) if name_div else "")
        team_name = acad_div.get_text(strip=True) if acad_div else ""
        points = pts_td.get_text(strip=True) if pts_td else "0"
        rank = pos_td.get_text(strip=True) if pos_td else ""

        athlete_id = None
        if photo_td:
            img = photo_td.find("img")
            if img and img.get("src"):
                m = re.search(r"/Athletes/(\d+)/", img["src"])
                if m:
                    athlete_id = int(m.group(1))

        if athlete_name:
            athletes.append({
                "name": athlete_name,
                "team": team_name,
                "points": points,
                "athleteId": athlete_id,
                "rank": int(rank) if rank.isdigit() else None,
                "belt": belt,
                "ageDiv": age_division,
                "gender": gender,
            })

    has_next = soup.find("li", class_="pagination-next") is not None
    return athletes, has_next


def scrape_combo(
    client: httpx.Client,
    belt: str,
    gender: str,
    age_division: str,
    max_pages: int,
) -> list[dict]:
    """Scrape all pages for one belt/gender/age combo."""
    all_athletes: list[dict] = []
    for page in range(1, max_pages + 1):
        try:
            athletes, has_next = fetch_ranking_page(client, belt, gender, age_division, page)
        except Exception as e:
            print(f"    [WARN] page {page} failed: {e}")
            break
        all_athletes.extend(athletes)
        if not has_next:
            break
    return all_athletes


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="IBJJF Rankings Scraper")
    parser.add_argument("--quick", action="store_true", help="Adult belts only (skip masters)")
    parser.add_argument("--max-pages", type=int, default=200, help="Max pages per combo (default 200)")
    args = parser.parse_args()

    combos = QUICK_COMBOS if args.quick else FULL_COMBOS
    print(f"Scraping {len(combos)} ranking combos (max {args.max_pages} pages each)...")

    client = httpx.Client(headers=HEADERS, follow_redirects=True, timeout=30)
    all_athletes: list[dict] = []
    seen: set[str] = set()  # deduplicate by name+belt+age+gender

    try:
        for i, (belt, gender, age) in enumerate(combos, 1):
            print(f"  [{i}/{len(combos)}] {age} / {belt} / {gender}", end="", flush=True)
            athletes = scrape_combo(client, belt, gender, age, args.max_pages)

            added = 0
            for a in athletes:
                key = f"{a['name'].lower()}|{a['belt']}|{a['ageDiv']}|{a['gender']}"
                if key not in seen:
                    seen.add(key)
                    all_athletes.append(a)
                    added += 1

            print(f" → {added} athletes ({len(athletes)} total on pages)")
    finally:
        client.close()

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "athleteCount": len(all_athletes),
        "athletes": all_athletes,
    }

    OUTPUT_FILE.write_text(json.dumps(payload, indent=2))
    print(f"\nWrote {len(all_athletes)} athletes → {OUTPUT_FILE}")

    # Sanity checks
    if all_athletes:
        belts = set(a["belt"] for a in all_athletes)
        genders_found = set(a["gender"] for a in all_athletes)
        print(f"  Belts: {', '.join(sorted(belts))}")
        print(f"  Genders: {', '.join(sorted(genders_found))}")


if __name__ == "__main__":
    main()
