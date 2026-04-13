"""
Client for scraping IBJJF event data.

Sources:
  - Calendar:      https://ibjjf.com/api/v1/events/calendar.json  (JSON, needs session cookie)
  - Event detail:  https://ibjjf.com/events/{slug}                 (server-rendered Rails HTML)
  - Registrations: https://www.ibjjfdb.com/ChampionshipResults/{id}/PublicRegistrations (ASP.NET HTML, inline JSON)
"""

from __future__ import annotations

import json
import re
import time
from datetime import datetime, date
from typing import Optional

import httpx
from bs4 import BeautifulSoup
from tenacity import retry, stop_after_attempt, wait_exponential

from models import Athlete, Division, Event, PriceTier

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

IBJJF_BASE = "https://ibjjf.com"
IBJJFDB_BASE = "https://www.ibjjfdb.com"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/123.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
}

# North America region name as it appears in the calendar API
NA_REGION = "North America"

# Cities that are in Canada or Mexico — used to exclude non-US events
# (IBJJF lumps the whole continent under "North America")
NON_US_CITIES = {
    "toronto", "montreal", "vancouver", "calgary", "ottawa",
    "mexico city", "guadalajara", "monterrey", "tijuana",
}

POLITE_DELAY = 1.0  # seconds between requests


# ---------------------------------------------------------------------------
# HTTP session helpers
# ---------------------------------------------------------------------------

def _make_client() -> httpx.Client:
    """Return an httpx client pre-seeded with a valid ibjjf.com session cookie."""
    client = httpx.Client(headers=HEADERS, follow_redirects=True, timeout=20)
    # Load the session cookie by hitting the calendar page first
    client.get(f"{IBJJF_BASE}/events/calendar")
    return client


# ---------------------------------------------------------------------------
# Calendar
# ---------------------------------------------------------------------------

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_calendar(client: httpx.Client) -> list[dict]:
    """Return upcoming US events from the IBJJF calendar JSON endpoint."""
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

    upcoming_us = []
    for e in events:
        if e.get("region") != NA_REGION:
            continue
        if e.get("status") == "finished":
            continue
        if e.get("city", "").lower() in NON_US_CITIES:
            continue
        if not e.get("pageUrl"):
            continue
        upcoming_us.append(e)

    return upcoming_us


# ---------------------------------------------------------------------------
# Event detail (price tiers + championship id confirmation)
# ---------------------------------------------------------------------------

def _parse_month_year(month: str, year: int, start_day: int, end_day: int) -> tuple[str, str]:
    """Convert calendar fields to ISO date strings."""
    MONTHS = {
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
    }
    m = MONTHS.get(month, 1)
    start = date(year, m, start_day).isoformat()
    end = date(year, m, end_day).isoformat()
    return start, end


def _parse_price_string(raw: str) -> tuple[float, str]:
    """
    Parse a price-string div like '$138.00 (USD)   until April 17th, 2026'.
    Returns (price_float, deadline_iso_date).
    """
    price_match = re.search(r"\$([\d.]+)", raw)
    price = float(price_match.group(1)) if price_match else 0.0

    # Parse date: "until April 17th, 2026" or "until May 8th, 2026"
    date_match = re.search(
        r"until\s+(\w+)\s+(\d+)(?:st|nd|rd|th)?,?\s+(\d{4})", raw, re.IGNORECASE
    )
    if date_match:
        month_name, day, year = date_match.groups()
        try:
            deadline = datetime.strptime(f"{month_name} {day} {year}", "%B %d %Y").date().isoformat()
        except ValueError:
            deadline = ""
    else:
        deadline = ""

    return price, deadline


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_event_detail(
    client: httpx.Client, slug: str, event_id: int
) -> tuple[int, list[PriceTier], str, str]:
    """
    Fetch the ibjjf.com event detail page and return
    (championship_id, price_tiers, venue, address).
    """
    time.sleep(POLITE_DELAY)
    resp = client.get(f"{IBJJF_BASE}{slug}", headers={**HEADERS, "Accept": "text/html"})
    resp.raise_for_status()
    soup = BeautifulSoup(resp.text, "lxml")

    # Confirm championship ID from links like /ChampionshipResults/3175/
    champ_id = event_id  # fallback
    id_match = re.search(r"/ChampionshipResults/(\d+)/", resp.text)
    if id_match:
        champ_id = int(id_match.group(1))

    # Parse price tiers
    price_tiers: list[PriceTier] = []
    for price_block in soup.select("div.price"):
        title_el = price_block.select_one(".price-title")
        title = title_el.get_text(strip=True) if title_el else "Standard"
        for ps in price_block.select(".price-string"):
            raw = ps.get_text(" ", strip=True)
            amount, deadline = _parse_price_string(raw)
            if amount and deadline:
                price_tiers.append(PriceTier(name=title, price=amount, deadline=deadline))

    # Parse venue and address from <address> block
    venue = ""
    address = ""
    addr_block = soup.select_one("address")
    if addr_block:
        venue = (addr_block.select_one(".local") or addr_block).get_text(strip=True)
        street = (addr_block.select_one(".address_lines") or addr_block).get_text(strip=True) if addr_block.select_one(".address_lines") else ""
        city   = addr_block.select_one(".complement")
        city   = city.get_text(strip=True) if city else ""
        state_zip = addr_block.select_one(".complement2")
        state_zip = re.sub(r"\s*-\s*", " ", state_zip.get_text(strip=True)) if state_zip else ""
        parts = [p for p in [street, city, state_zip] if p]
        address = ", ".join(parts)

    return champ_id, price_tiers, venue, address


# ---------------------------------------------------------------------------
# Registrations
# ---------------------------------------------------------------------------

def _parse_friendly_name(friendly: str) -> tuple[str, str, str, str]:
    """
    Parse "WHITE / Adult / Male / Rooster (127.00lb)" into
    (belt, age_division, gender, weight_class).
    """
    parts = [p.strip() for p in friendly.split("/")]
    if len(parts) >= 4:
        belt = parts[0]
        age = parts[1]
        gender = parts[2]
        weight = re.sub(r"\s*\(.*?\)", "", parts[3]).strip()
        return belt, age, gender, weight
    return friendly, "", "", ""


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def fetch_registrations(champ_id: int) -> list[Division]:
    """
    Fetch the public registrations page for a championship and return Division objects.
    Uses a fresh client (no session cookie needed for www.ibjjfdb.com).
    """
    time.sleep(POLITE_DELAY)
    url = f"{IBJJFDB_BASE}/ChampionshipResults/{champ_id}/PublicRegistrations?lang=en-US"
    resp = httpx.get(url, headers=HEADERS, follow_redirects=True, timeout=20)
    resp.raise_for_status()

    # Extract inline model JSON
    match = re.search(r"const model = (\[.*?\]);", resp.text, re.DOTALL)
    if not match:
        return []

    raw_model: list[dict] = json.loads(match.group(1))
    divisions: list[Division] = []
    for entry in raw_model:
        belt, age, gender, weight = _parse_friendly_name(entry.get("FriendlyName", ""))
        athletes = [
            Athlete(name=a["AthleteName"], team=a.get("AcademyTeamName", ""))
            for a in entry.get("RegistrationCategories", [])
        ]
        divisions.append(Division(
            belt=belt,
            ageDivision=age,
            gender=gender,
            weightClass=weight,
            athletes=athletes,
        ))

    return divisions


# ---------------------------------------------------------------------------
# High-level: build one Event object
# ---------------------------------------------------------------------------

def build_event(client: httpx.Client, raw: dict) -> Optional[Event]:
    """Combine calendar entry + event detail + registrations into an Event model."""
    slug = raw["pageUrl"]
    event_id = raw["id"]
    start, end = _parse_month_year(raw["month"], raw["year"], raw["startDay"], raw["endDay"])

    try:
        champ_id, price_tiers, venue, address = fetch_event_detail(client, slug, event_id)
    except Exception as e:
        print(f"  [WARN] Could not fetch detail for {slug}: {e}")
        champ_id, price_tiers, venue, address = event_id, [], "", ""

    try:
        divisions = fetch_registrations(champ_id)
    except Exception as e:
        print(f"  [WARN] Could not fetch registrations for {champ_id}: {e}")
        divisions = []

    return Event(
        id=event_id,
        name=raw["name"],
        slug=slug.lstrip("/events/"),
        startDate=start,
        endDate=end,
        city=raw.get("city", ""),
        country="US",
        venue=venue,
        address=address,
        registrationUrl=f"{IBJJFDB_BASE}/ChampionshipResults/{champ_id}/PublicRegistrations?lang=en-US",
        priceTiers=price_tiers,
        divisions=divisions,
    )
