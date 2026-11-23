"""What a family owes and what is late. Pure functions on integers (FCFA): no database, no float, easy to test.

Rule: payments and discounts are credits. They are imputed on the OLDEST due first (a partial payment is always accepted and
fills the earliest line). A credit note (cancelled payment) is a negative credit, so the line it had covered is open again.
"""

from dataclasses import dataclass
from datetime import date


@dataclass(frozen=True)
class Due:
    id: int
    kind: str
    label: str
    amount: int
    due_date: date


@dataclass(frozen=True)
class Line:
    id: int
    kind: str
    label: str
    amount: int
    due_date: date
    covered: int
    remaining: int
    late_days: int  # 0 when not late or fully covered


@dataclass(frozen=True)
class Account:
    lines: list[Line]
    total_due: int
    credited: int  # payments - credit notes + discounts
    remaining: int  # still to pay (never negative)
    overdue: int  # part of `remaining` whose date has passed
    credit_balance: int  # paid in advance / overpaid (never negative)


def applicable(fee_assigned_scope: str, student_assigned: bool) -> bool:
    return fee_assigned_scope == "all" or (fee_assigned_scope == "assigned") == student_assigned


def build_account(dues: list[Due], credited: int, today: date) -> Account:
    ordered = sorted(dues, key=lambda d: (d.due_date, d.id))
    pool = max(credited, 0)
    lines: list[Line] = []
    for d in ordered:
        covered = min(d.amount, pool)
        pool -= covered
        remaining = d.amount - covered
        late = (today - d.due_date).days if remaining > 0 and d.due_date < today else 0
        lines.append(Line(d.id, d.kind, d.label, d.amount, d.due_date, covered, remaining, late))
    total = sum(d.amount for d in dues)
    remaining_total = sum(line.remaining for line in lines)
    return Account(
        lines=lines,
        total_due=total,
        credited=credited,
        remaining=remaining_total,
        overdue=sum(line.remaining for line in lines if line.late_days > 0),
        credit_balance=pool,
    )
