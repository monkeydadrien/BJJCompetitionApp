from __future__ import annotations
from datetime import datetime
from pydantic import BaseModel


class PriceTier(BaseModel):
    name: str
    price: float
    deadline: str  # ISO 8601 string; parsing "April 17th, 2026" → "2026-04-17"


class Athlete(BaseModel):
    name: str
    team: str


class Division(BaseModel):
    belt: str
    ageDivision: str
    gender: str
    weightClass: str
    athletes: list[Athlete]

    @property
    def count(self) -> int:
        return len(self.athletes)


class Event(BaseModel):
    id: int
    name: str
    slug: str
    startDate: str   # "YYYY-MM-DD"
    endDate: str     # "YYYY-MM-DD"
    city: str
    country: str
    venue: str = ""       # e.g. "Silver Spurs Arena - Osceola Heritage Park"
    address: str = ""     # e.g. "1875 Silver Spur Ln, Kissimmee, FL 34744"
    registrationUrl: str
    priceTiers: list[PriceTier]
    divisions: list[Division]
    lat: float | None = None     # geocoded from "{city}, {country}"; nullable for back-compat
    lon: float | None = None


class EventsPayload(BaseModel):
    generatedAt: str
    events: list[Event]
