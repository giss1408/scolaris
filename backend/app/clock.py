"""The current time in ONE place, so tests can set it. Côte d'Ivoire is UTC+0 all year (no daylight saving)."""

from datetime import datetime, timezone


def now() -> datetime:
    return datetime.now(timezone.utc)
