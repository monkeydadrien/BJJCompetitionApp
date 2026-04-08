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

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from compsystem_client import fetch_bracket, fetch_categories, fetch_tournaments

app = FastAPI(title="BJJ Companion Proxy", version="1.0.0")

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

TOURNAMENTS_TTL = 60 * 60 * 24  # 24 hours — tournament list changes rarely
CATEGORIES_TTL = 60 * 60 * 24   # 24 hours
BRACKET_TTL = 60                  # 60 seconds — matches update frequently during event


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
def get_tournaments():
    """Return list of all tournaments."""
    try:
        return _cached("tournaments", TOURNAMENTS_TTL, fetch_tournaments)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/tournaments/{tournament_id}/categories")
def get_categories(tournament_id: int, gender_id: int = Query(default=1, ge=1, le=2)):
    """Return bracket categories for a tournament filtered by gender (1=Male, 2=Female)."""
    key = f"categories:{tournament_id}:{gender_id}"
    try:
        return _cached(key, CATEGORIES_TTL, lambda: fetch_categories(tournament_id, gender_id))
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/bracket")
def get_bracket(
    tournament: int = Query(..., description="Tournament ID"),
    category: int = Query(..., description="Category ID"),
):
    """Fetch and return the bracket tree for a specific division."""
    key = f"bracket:{tournament}:{category}"
    try:
        return _cached(key, BRACKET_TTL, lambda: fetch_bracket(tournament, category))
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))


@app.get("/health")
def health():
    return {"status": "ok"}
