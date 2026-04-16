#!/usr/bin/env python3
"""
Daily scraper entrypoint.

Usage:
  python scrape.py              # Scrape all upcoming US events → events.json
  python scrape.py --dry-run    # Use fixture data only (no network calls)
  python scrape.py --limit N    # Only process first N events (for testing)
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from ibjjf_client import build_event, fetch_calendar, _make_client
from geocode import geocode, load_cache, save_cache
from models import EventsPayload

OUTPUT_FILE = Path(__file__).parent.parent / "events.json"
FIXTURES_DIR = Path(__file__).parent / "fixtures"


def scrape_live(limit: int | None) -> EventsPayload:
    print("Fetching IBJJF calendar...")
    client = _make_client()
    raw_events = fetch_calendar(client)
    print(f"  Found {len(raw_events)} upcoming US events")

    if limit:
        raw_events = raw_events[:limit]
        print(f"  Limited to {limit} for this run")

    events = []
    for i, raw in enumerate(raw_events, 1):
        print(f"  [{i}/{len(raw_events)}] {raw['name']} (id={raw['id']})")
        event = build_event(client, raw)
        if event:
            events.append(event)

    # Geocode city/country → lat/lon. Cached in geocode_cache.json so repeat
    # runs (CI nightly + local re-runs) hit Nominatim only for new cities.
    print("\nGeocoding event locations...")
    geo_cache = load_cache()
    cache_size_before = len(geo_cache)
    for ev in events:
        ev.lat, ev.lon = geocode(ev.city, ev.country, geo_cache)
    save_cache(geo_cache)
    new_lookups = len(geo_cache) - cache_size_before
    with_coords = sum(1 for e in events if e.lat is not None)
    print(f"  Geocoded {with_coords}/{len(events)} events "
          f"({new_lookups} new cache entries, {len(geo_cache)} total cached)")

    return EventsPayload(
        generatedAt=datetime.now(timezone.utc).isoformat(),
        events=events,
    )


def scrape_dry_run() -> EventsPayload:
    """Build payload from local fixture files (no network)."""
    print("DRY RUN: using fixture files")
    calendar_path = FIXTURES_DIR / "calendar.json"
    if not calendar_path.exists():
        print("ERROR: fixtures/calendar.json not found. Run the live scraper first.")
        sys.exit(1)

    with open(calendar_path) as f:
        raw_events = json.load(f)["infosite_events"]

    import re
    from ibjjf_client import _parse_month_year, _parse_price_string, _parse_friendly_name, _make_client
    from models import Athlete, Division, Event, PriceTier
    from bs4 import BeautifulSoup

    events = []
    for raw in raw_events[:3]:  # dry run: first 3 from fixture
        event_id = raw["id"]
        slug = raw.get("pageUrl", "")
        start, end = _parse_month_year(raw["month"], raw["year"], raw["startDay"], raw["endDay"])

        # Try loading matching fixture files
        detail_fixture = FIXTURES_DIR / f"event_detail_{event_id}.html"
        reg_fixture = FIXTURES_DIR / f"registrations_{event_id}.json"

        price_tiers: list[PriceTier] = []
        if detail_fixture.exists():
            soup = BeautifulSoup(detail_fixture.read_text(), "lxml")
            for price_block in soup.select("div.price"):
                title_el = price_block.select_one(".price-title")
                title = title_el.get_text(strip=True) if title_el else "Standard"
                for ps in price_block.select(".price-string"):
                    raw_ps = ps.get_text(" ", strip=True)
                    amount, deadline = _parse_price_string(raw_ps)
                    if amount and deadline:
                        price_tiers.append(PriceTier(name=title, price=amount, deadline=deadline))

        divisions: list[Division] = []
        if reg_fixture.exists():
            raw_model = json.loads(reg_fixture.read_text())
            for entry in raw_model:
                belt, age, gender, weight = _parse_friendly_name(entry.get("FriendlyName", ""))
                athletes = [
                    Athlete(name=a["AthleteName"], team=a.get("AcademyTeamName", ""))
                    for a in entry.get("RegistrationCategories", [])
                ]
                divisions.append(Division(
                    belt=belt, ageDivision=age, gender=gender,
                    weightClass=weight, athletes=athletes,
                ))

        events.append(Event(
            id=event_id,
            name=raw["name"],
            slug=slug.lstrip("/events/"),
            startDate=start,
            endDate=end,
            city=raw.get("city", ""),
            country="US",
            registrationUrl=f"https://www.ibjjfdb.com/ChampionshipResults/{event_id}/PublicRegistrations?lang=en-US",
            priceTiers=price_tiers,
            divisions=divisions,
        ))
        print(f"  Built (fixture): {raw['name']}  prices={len(price_tiers)}  divisions={len(divisions)}")

    return EventsPayload(
        generatedAt=datetime.now(timezone.utc).isoformat(),
        events=events,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="IBJJF event scraper")
    parser.add_argument("--dry-run", action="store_true", help="Use fixture data, no network")
    parser.add_argument("--limit", type=int, default=None, help="Max events to process")
    args = parser.parse_args()

    if args.dry_run:
        payload = scrape_dry_run()
    else:
        payload = scrape_live(args.limit)

    out = OUTPUT_FILE
    out.write_text(json.dumps(payload.model_dump(), indent=2))
    print(f"\nWrote {len(payload.events)} events → {out}")

    # Basic assertions
    assert len(payload.events) >= 1, "No events found!"
    if not args.dry_run:
        events_with_prices = [e for e in payload.events if e.priceTiers]
        events_with_divisions = [e for e in payload.events if e.divisions]
        print(f"  Events with price tiers: {len(events_with_prices)}/{len(payload.events)}")
        print(f"  Events with divisions:   {len(events_with_divisions)}/{len(payload.events)}")


if __name__ == "__main__":
    main()
