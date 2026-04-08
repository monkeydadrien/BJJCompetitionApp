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
    registrationUrl: str
    priceTiers: list[PriceTier]
    divisions: list[Division]


class EventsPayload(BaseModel):
    generatedAt: str
    events: list[Event]
