"""
Lightweight FastAPI proxy for on-demand bracket fetching.

Endpoints:
  GET /tournaments                              → cached tournament list
  GET /tournaments/{tid}/categories?gender_id= → cached categories
  GET /bracket?tournament={tid}&category={cid} → on-demand bracket (60s cache)

Run locally:
  uvicorn proxy:app --reload --port 8000

AWS migration: wrap with Mangum for API Gateway + Lambda.
  from mangum import Mangum
  handler = Mangum(app)
"""

from __future__ import annotations

import time
from functools import lru_cache
from typing import Optional

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from compsystem_client import (
    fetch_bracket,
    fetch_categories,
    fetch_tournaments,
    fetch_all_tournament_matches,
)

app = FastAPI(title="BJJ Companion Proxy", version="1.0.0")

# Rate limiter — keyed by client IP. Fly is configured to forward real IPs
# via --proxy-headers / --forwarded-allow-ips in the Dockerfile CMD.
limiter = Limiter(key_func=get_remote_address, default_limits=["60/minute"])
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # iOS app hits this directly; tighten in prod if needed
    allow_methods=["GET"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Simple in-process cache (TTL in seconds)
# ---------------------------------------------------------------------------

_cache: dict[str, tuple[float, object]] = {}

TOURNAMENTS_TTL  = 60 * 60 * 24  # 24 hours — tournament list changes rarely
CATEGORIES_TTL   = 60 * 60 * 24  # 24 hours
BRACKET_TTL      = 60             # 60 seconds — matches update during event
SCHEDULE_TTL     = 5 * 60         # 5 minutes — full tournament scan cache


def _cached(key: str, ttl: float, fn):
    now = time.monotonic()
    if key in _cache:
        ts, val = _cache[key]
        if now - ts < ttl:
            return val
    val = fn()
    _cache[key] = (now, val)
    return val


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/tournaments")
@limiter.limit("60/minute")
def get_tournaments(request: Request):
    """Return list of all tournaments."""
    try:
        return _cached("tournaments", TOURNAMENTS_TTL, fetch_tournaments)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/tournaments/{tournament_id}/categories")
@limiter.limit("60/minute")
def get_categories(request: Request, tournament_id: int, gender_id: int = Query(default=1, ge=1, le=2)):
    """Return bracket categories for a tournament filtered by gender (1=Male, 2=Female)."""
    key = f"categories:{tournament_id}:{gender_id}"
    try:
        return _cached(key, CATEGORIES_TTL, lambda: fetch_categories(tournament_id, gender_id))
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bracket")
@limiter.limit("60/minute")
def get_bracket(
    request: Request,
    tournament: int = Query(..., description="Tournament ID"),
    category: int = Query(..., description="Category ID"),
):
    """Fetch and return the bracket tree for a specific division."""
    key = f"bracket:{tournament}:{category}"
    try:
        return _cached(key, BRACKET_TTL, lambda: fetch_bracket(tournament, category))
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/schedule")
@limiter.limit("5/minute")
def get_schedule(
    request: Request,
    tournament: int = Query(..., description="Tournament ID"),
    names: str = Query(..., description="Comma-separated athlete names and/or team names to search for"),
):
    """
    Return all matches across every bracket in a tournament where any competitor's
    name or club matches one of the queried names (case-insensitive substring match).

    The full bracket scan is cached for SCHEDULE_TTL seconds — expensive first call,
    instant thereafter. Name filtering is applied per-request on the cached data.
    """
    name_list = [n.strip().lower() for n in names.split(",") if n.strip()]
    if not name_list:
        raise HTTPException(status_code=400, detail="names parameter must not be empty")

    # Cache the full tournament bracket scan (expensive) — filter per request (cheap)
    cache_key = f"all_brackets:{tournament}"
    try:
        all_matches: list[dict] = _cached(
            cache_key, SCHEDULE_TTL,
            lambda: fetch_all_tournament_matches(tournament),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    # Filter matches where any competitor matches any tracked name
    results: list[dict] = []
    seen: set[tuple] = set()

    for match in all_matches:
        competitors = match.get("competitors", [])
        for i, comp in enumerate(competitors):
            comp_name = (comp.get("name") or "").lower()
            comp_club = (comp.get("club") or "").lower()

            hit = any(
                tracked and (tracked in comp_name or tracked in comp_club)
                for tracked in name_list
            )
            if not hit:
                continue

            # Deduplicate: one entry per (category, fight, competitor-index)
            dedup_key = (match.get("categoryId"), match.get("fight"), i)
            if dedup_key in seen:
                continue
            seen.add(dedup_key)

            # Build opponent string from the other slot
            opponent = None
            for j, other in enumerate(competitors):
                if j != i:
                    opponent = other.get("name") or other.get("placeholder")

            results.append({
                "athleteName":   comp.get("name"),
                "teamName":      comp.get("club", ""),
                "categoryLabel": match.get("categoryLabel", ""),
                "categoryId":    match.get("categoryId"),
                "tournamentId":  tournament,
                "fight":         match.get("fight"),
                "mat":           match.get("mat"),
                "when":          match.get("when"),
                "round":         match.get("round"),
                "opponent":      opponent,
            })

    # Sort by time then fight number for predictable ordering
    results.sort(key=lambda m: (m.get("when") or "99:99", m.get("fight") or 9999))

    return {"tournamentId": tournament, "matches": results}


@app.get("/health")
def health():
    return {"status": "ok"}
