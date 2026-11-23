"""What a school owes Scolaris each month, and whether it is late. Same due-date engine as the families' fees (oldest instalment paid first)."""

from datetime import date

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Subscription, SubscriptionPayment
from app.services.billing import Account, Due, build_account


def _add_month(d: date, day: int) -> date:
    y, m = (d.year + (d.month // 12), d.month % 12 + 1)
    return date(y, m, day)


def dues_until(sub: Subscription, today: date) -> list[Due]:
    """One instalment per month, each due on `billing_day`, the first one on or after the start date, up to today."""
    d = date(sub.started_on.year, sub.started_on.month, sub.billing_day)
    if d < sub.started_on:
        d = _add_month(d, sub.billing_day)
    out: list[Due] = []
    while d <= today and len(out) < 240:
        out.append(Due(len(out), "mensualite", f"Mensualité {d:%m/%Y}", sub.monthly_amount, d))
        d = _add_month(d, sub.billing_day)
    return out


def next_due(sub: Subscription, today: date) -> date:
    d = date(sub.started_on.year, sub.started_on.month, sub.billing_day)
    if d < sub.started_on:
        d = _add_month(d, sub.billing_day)
    while d <= today:
        d = _add_month(d, sub.billing_day)
    return d


async def standing(db: AsyncSession, school_id: int, today: date) -> dict | None:
    """The school's account with Scolaris, or None when no subscription was set up (a free pilot school is never late)."""
    sub = await db.get(Subscription, school_id)
    if sub is None:
        return None
    paid = int(await db.scalar(select(func.coalesce(func.sum(SubscriptionPayment.amount), 0)).where(SubscriptionPayment.school_id == school_id)) or 0)
    acct: Account = build_account(dues_until(sub, today), paid, today)
    late_lines = [ln for ln in acct.lines if ln.remaining > 0 and ln.late_days > 0]
    oldest = max((ln.late_days for ln in late_lines), default=0)
    return {
        "monthly_amount": sub.monthly_amount, "billing_day": sub.billing_day, "grace_days": sub.grace_days, "started_on": sub.started_on.isoformat(),
        "billed": acct.total_due, "paid": paid, "remaining": acct.remaining, "overdue_months": len(late_lines), "oldest_late_days": oldest,
        "late": oldest > sub.grace_days,  # late = the oldest unpaid instalment is past the grace period
        "credit": acct.credit_balance, "next_due": next_due(sub, today).isoformat(),
        "lines": [{"label": ln.label, "amount": ln.amount, "due_date": ln.due_date.isoformat(), "covered": ln.covered, "remaining": ln.remaining, "late_days": ln.late_days} for ln in acct.lines],
    }
