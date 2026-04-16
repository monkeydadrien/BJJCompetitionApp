"""
Lightweight Nominatim geocoder with a JSON file cache.

The cache file (geocode_cache.json) lives next to this module and is committed
to the repo so CI runs are O(0) network for previously-seen cities. Nominatim's
ToS limits us to ~1 req/sec; we sleep between live calls.

Usage:
    from geocode import geocode, load_cache, save_cache

    cache = load_cache()
    lat, lon = geocode("Las Vegas", "US", cache)
    save_cache(cache)
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Optional

import httpx

CACHE_FILE = Path(__file__).parent / "geocode_cache.json"
NOMINATIM = "https://nominatim.openstreetmap.org/search"
USER_AGENT = "BJJCompanion/1.0 (https://github.com/monkeydadrien/BJJCompetitionApp)"
POLITE_DELAY = 1.1  # Nominatim ToS: ≤1 req/sec


def _key(city: str, country: str) -> str:
    return f"{city.strip()}, {country.strip()}".lower()


def load_cache() -> dict:
    if CACHE_FILE.exists():
        try:
            return json.loads(CACHE_FILE.read_text())
        except json.JSONDecodeError:
            print(f"  WARN: {CACHE_FILE.name} is corrupt — starting fresh")
    return {}


def save_cache(cache: dict) -> None:
    CACHE_FILE.write_text(json.dumps(cache, indent=2, sort_keys=True))


def geocode(
    city: str,
    country: str,
    cache: dict,
) -> tuple[Optional[float], Optional[float]]:
    """
    Look up (lat, lon) for "{city}, {country}". Cached aggressively, including
    misses (cached as nulls so we don't keep re-hitting Nominatim for unparseable
    locations).
    """
    if not city:
        return None, None

    key = _key(city, country)
    if key in cache:
        entry = cache[key]
        return entry.get("lat"), entry.get("lon")

    time.sleep(POLITE_DELAY)
    try:
        r = httpx.get(
            NOMINATIM,
            params={"q": key, "format": "json", "limit": 1},
            headers={"User-Agent": USER_AGENT},
            timeout=15,
        )
        r.raise_for_status()
        results = r.json()
    except Exception as e:
        print(f"  geocode failed for {key}: {e}")
        return None, None

    if not results:
        cache[key] = {"lat": None, "lon": None}
        return None, None

    try:
        lat = float(results[0]["lat"])
        lon = float(results[0]["lon"])
    except (KeyError, TypeError, ValueError):
        cache[key] = {"lat": None, "lon": None}
        return None, None

    cache[key] = {"lat": lat, "lon": lon}
    return lat, lon
