"""Averages, ranks and honours. Pure functions on Decimals (no database): the rules of the Ivorian report card in one testable place.

- A grade out of `max_score` is brought to /20. An absent pupil has no grade (it is NOT a zero) and is left out of the average.
- Subject average of a period = mean of that subject's grades. Period average = sum(average x coef) / sum(coef) over the subjects
  that have an average AND a coefficient > 0 (a subject without any grade yet does not drag the average down).
- Annual average = mean of the period averages that exist.
- Rank: higher average first; equal averages share the rank ("3e ex"), the next rank skips.
"""

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from app.levels import DEFAULT_HONOURS, PASS_MARK

TWO = Decimal("0.01")


def q(x: Decimal) -> Decimal:
    return x.quantize(TWO, rounding=ROUND_HALF_UP)


def to_twenty(value: Decimal, max_score: int) -> Decimal:
    return value * Decimal(20) / Decimal(max_score)


def subject_average(grades: list[tuple[Decimal | None, int, bool]]) -> Decimal | None:
    """grades = (value, max_score, absent). None when nothing is countable."""
    vals = [to_twenty(v, m) for v, m, absent in grades if not absent and v is not None]
    return q(sum(vals) / len(vals)) if vals else None


def period_average(subject_avgs: dict[int, Decimal | None], coefs: dict[int, int]) -> Decimal | None:
    num = Decimal(0)
    den = 0
    for sid, avg in subject_avgs.items():
        c = coefs.get(sid, 0)
        if avg is None or c <= 0:
            continue
        num += avg * c
        den += c
    return q(num / den) if den else None


def annual_average(period_avgs: list[Decimal | None]) -> Decimal | None:
    vals = [a for a in period_avgs if a is not None]
    return q(sum(vals) / len(vals)) if vals else None


@dataclass(frozen=True)
class Rank:
    position: int
    tie: bool  # "3e ex"
    of: int


def rank_all(averages: dict[int, Decimal | None]) -> dict[int, Rank]:
    """Ranks for the pupils that HAVE an average (the others are not ranked)."""
    ranked = sorted(((k, v) for k, v in averages.items() if v is not None), key=lambda kv: -kv[1])
    out: dict[int, Rank] = {}
    n = len(ranked)
    pos = 0
    prev: Decimal | None = None
    for i, (k, v) in enumerate(ranked, start=1):
        if v != prev:
            pos = i
            prev = v
        out[k] = Rank(pos, False, n)
    counts: dict[int, int] = {}
    for r in out.values():
        counts[r.position] = counts.get(r.position, 0) + 1
    return {k: Rank(r.position, counts[r.position] > 1, r.of) for k, r in out.items()}


def honour(avg: Decimal | None, thresholds: dict | None = None) -> str | None:
    """Félicitations / Encouragements / Tableau d'honneur by the period average (thresholds are the school's)."""
    if avg is None:
        return None
    t = {**DEFAULT_HONOURS, **(thresholds or {})}
    for key in ("felicitations", "encouragements", "tableau_honneur"):
        if avg >= Decimal(str(t[key])):
            return key
    return None


def passes(avg: Decimal | None) -> bool | None:
    return None if avg is None else avg >= Decimal(str(PASS_MARK))
