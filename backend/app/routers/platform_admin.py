"""The Scolaris team (platform admins): each school's monthly subscription, reminders sent in the app, and blocking a school that stays late.

Blocking is deliberate and slow by design: the school must be late beyond its grace period, must have received reminders AND a final notice
(in the app, visible to its director and its secretary), the date announced in the final notice must have passed, and the admin re-proves her
password. Every action is written to the platform audit log."""

from datetime import date, timedelta

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.db import get_session
from app.deps import AdminMe, current_admin
from app.errors import BadRequest, Conflict, NotFound
from app.levels import PAYMENT_METHODS
from app.models import PlatformAudit, School, SchoolNotice, SchoolNoticeSeen, StaffMember, Subscription, SubscriptionPayment
from app.services import saas_billing
from app.services.reminders import money

router = APIRouter(prefix="/v1/platform", tags=["platform"])
FINAL_NOTICE_MIN_DAYS = 7  # the final notice announces a block date at least a week ahead
MIN_REMINDERS = 1  # reminders (not counting the final notice) before a final notice may be sent


class SubscriptionIn(BaseModel):
    monthly_amount: int = Field(gt=0, le=100_000_000)
    billing_day: int = Field(ge=1, le=28)
    started_on: date
    grace_days: int = Field(default=5, ge=0, le=60)


class PaymentIn(BaseModel):
    amount: int = Field(gt=0, le=1_000_000_000)
    method: str
    reference: str | None = Field(default=None, max_length=80)
    paid_on: date | None = None


class NoticeIn(BaseModel):
    kind: str = Field(pattern="^(reminder|final_notice|info)$")
    block_on: date | None = None  # final notice only
    title: str | None = Field(default=None, max_length=120)  # info only
    text: str | None = Field(default=None, max_length=1000)  # info only


class BlockIn(BaseModel):
    reason: str = Field(min_length=3, max_length=240)


async def _school(db: AsyncSession, school_id: int) -> School:
    s = await db.get(School, school_id)
    if s is None:
        raise NotFound("school_not_found")
    return s


def _audit(db: AsyncSession, admin: AdminMe, school_id: int | None, action: str, **detail) -> None:
    db.add(PlatformAudit(admin=admin.id, school_id=school_id, action=action, detail=detail))


async def _notice_stats(db: AsyncSession, school_id: int) -> dict:
    rows = (await db.scalars(select(SchoolNotice).where(SchoolNotice.school_id == school_id).order_by(SchoolNotice.id))).all()
    reminders = [n for n in rows if n.kind == "reminder"]
    finals = [n for n in rows if n.kind == "final_notice"]
    return {"reminders": len(reminders), "final_notices": len(finals), "last_notice_at": rows[-1].created_at.isoformat() if rows else None,
            "last_final_block_on": finals[-1].block_on.isoformat() if finals and finals[-1].block_on else None}


@router.get("/schools")
async def schools(admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> list[dict]:
    today = clock.now().date()
    out = []
    for s in (await db.scalars(select(School).order_by(School.name))).all():
        st = await saas_billing.standing(db, s.id, today)
        out.append({"id": s.id, "name": s.name, "city": s.city, "status": s.status, "blocked_at": s.blocked_at.isoformat() if s.blocked_at else None,
                    "subscription": None if st is None else {k: st[k] for k in ("monthly_amount", "remaining", "overdue_months", "oldest_late_days", "late", "next_due")},
                    **await _notice_stats(db, s.id)})
    # the late ones first: that is what the team acts on
    return sorted(out, key=lambda r: (r["status"] != "blocked", not (r["subscription"] or {}).get("late", False), -(r["subscription"] or {}).get("oldest_late_days", 0), r["name"]))


@router.get("/schools/{school_id}")
async def school_detail(school_id: int, admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> dict:
    s = await _school(db, school_id)
    today = clock.now().date()
    notices = (await db.scalars(select(SchoolNotice).where(SchoolNotice.school_id == s.id).order_by(SchoolNotice.id.desc()))).all()
    audience = int(await db.scalar(select(func.count()).select_from(StaffMember).where(StaffMember.school_id == s.id, StaffMember.active, StaffMember.role.in_(("director", "secretary")))) or 0)
    seen = {nid: n for nid, n in (await db.execute(select(SchoolNoticeSeen.notice_id, func.count()).group_by(SchoolNoticeSeen.notice_id))).all()}
    pays = (await db.scalars(select(SubscriptionPayment).where(SubscriptionPayment.school_id == s.id).order_by(SubscriptionPayment.paid_on.desc(), SubscriptionPayment.id.desc()))).all()
    return {
        "school": {"id": s.id, "name": s.name, "city": s.city, "status": s.status, "blocked_at": s.blocked_at.isoformat() if s.blocked_at else None, "blocked_reason": s.blocked_reason},
        "subscription": await saas_billing.standing(db, s.id, today), **await _notice_stats(db, s.id),
        "payments": [{"id": p.id, "amount": p.amount, "method": p.method, "reference": p.reference, "paid_on": p.paid_on.isoformat()} for p in pays],
        "notices": [{"id": n.id, "kind": n.kind, "title": n.title, "text": n.text, "block_on": n.block_on.isoformat() if n.block_on else None, "created_at": n.created_at.isoformat(),
                     "seen_by": seen.get(n.id, 0), "audience": audience} for n in notices],
    }


@router.put("/schools/{school_id}/subscription")
async def set_subscription(school_id: int, data: SubscriptionIn, admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> dict:
    s = await _school(db, school_id)
    sub = await db.get(Subscription, s.id)
    if sub is None:
        sub = Subscription(school_id=s.id, monthly_amount=data.monthly_amount, billing_day=data.billing_day, started_on=data.started_on, grace_days=data.grace_days, updated_by=admin.id)
        db.add(sub)
    else:
        sub.monthly_amount, sub.billing_day, sub.started_on, sub.grace_days, sub.updated_by = data.monthly_amount, data.billing_day, data.started_on, data.grace_days, admin.id
    _audit(db, admin, s.id, "subscription.set", monthly_amount=data.monthly_amount, billing_day=data.billing_day, started_on=data.started_on.isoformat())
    await db.commit()
    return await saas_billing.standing(db, s.id, clock.now().date())


@router.post("/schools/{school_id}/payments", status_code=201)
async def record_payment(school_id: int, data: PaymentIn, admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> dict:
    """A payment received from the school (the team checks the transfer or Mobile Money receipt, then records it here)."""
    await admin.require_recent_password()
    s = await _school(db, school_id)
    if data.method not in PAYMENT_METHODS:
        raise BadRequest("method_invalid")
    if await db.get(Subscription, s.id) is None:
        raise BadRequest("no_subscription", "Définissez d'abord l'abonnement de cette école.")
    p = SubscriptionPayment(school_id=s.id, amount=data.amount, method=data.method, reference=(data.reference or "").strip() or None, paid_on=data.paid_on or clock.now().date(), recorded_by=admin.id)
    db.add(p)
    _audit(db, admin, s.id, "subscription.payment", amount=data.amount, method=data.method)
    await db.commit()
    st = await saas_billing.standing(db, s.id, clock.now().date())
    return {"payment_id": p.id, "standing": st, "can_unblock": s.status == "blocked" and st["remaining"] == 0}


def _notice_text(kind: str, st: dict, block_on: date | None) -> tuple[str, str]:
    owed = f"{money(st['remaining'])} ({st['overdue_months']} mensualité{'s' if st['overdue_months'] > 1 else ''}, la plus ancienne en retard de {st['oldest_late_days']} jours)"
    if kind == "reminder":
        return ("Rappel : mensualité Scolaris en retard", f"La mensualité de votre établissement est en retard : {owed}. Merci de régulariser dès que possible. Pour toute question, répondez à l'équipe Scolaris.")
    return ("Dernier avis avant suspension", f"{owed}. Sans règlement avant le {block_on:%d/%m/%Y}, l'accès de votre établissement (personnel et parents) sera suspendu. Régularisez avant cette date pour l'éviter.")


@router.post("/schools/{school_id}/notices", status_code=201)
async def send_notice(school_id: int, data: NoticeIn, admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> dict:
    """A reminder, a final notice or an information, shown in the app to the school's director AND secretary."""
    s = await _school(db, school_id)
    today = clock.now().date()
    block_on = None
    if data.kind == "info":
        if not data.title or not data.text:
            raise BadRequest("title_and_text_required")
        title, text = data.title, data.text
    else:
        st = await saas_billing.standing(db, s.id, today)
        if st is None or not st["late"]:
            raise BadRequest("not_late", "Cette école n'est pas en retard de paiement.")
        if data.kind == "final_notice":
            stats = await _notice_stats(db, s.id)
            if stats["reminders"] < MIN_REMINDERS:
                raise BadRequest("reminder_first", "Envoyez d'abord au moins un rappel avant le dernier avis.")
            if data.block_on is None or data.block_on < today + timedelta(days=FINAL_NOTICE_MIN_DAYS):
                raise BadRequest("block_date_too_soon", f"La date de suspension annoncée doit être au moins {FINAL_NOTICE_MIN_DAYS} jours après aujourd'hui.")
            block_on = data.block_on
        title, text = _notice_text(data.kind, st, block_on)
    n = SchoolNotice(school_id=s.id, kind=data.kind, title=title, text=text, block_on=block_on, created_by=admin.id)
    db.add(n)
    _audit(db, admin, s.id, f"notice.{data.kind}", block_on=block_on.isoformat() if block_on else None)
    await db.commit()
    return {"id": n.id, "kind": n.kind, "title": n.title, "text": n.text, "block_on": block_on.isoformat() if block_on else None}


@router.post("/schools/{school_id}/block")
async def block_school(school_id: int, data: BlockIn, admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> dict:
    await admin.require_recent_password()
    s = await _school(db, school_id)
    if s.status == "blocked":
        raise Conflict("already_blocked")
    today = clock.now().date()
    st = await saas_billing.standing(db, s.id, today)
    if st is None or not st["late"]:
        raise BadRequest("not_late", "Cette école n'est pas en retard au-delà de son délai de grâce.")
    stats = await _notice_stats(db, s.id)
    if stats["reminders"] < MIN_REMINDERS:
        raise BadRequest("reminders_required", "Envoyez d'abord des rappels dans l'application.")
    if stats["final_notices"] < 1:
        raise BadRequest("final_notice_required", "Envoyez d'abord le dernier avis annonçant la date de suspension.")
    if stats["last_final_block_on"] is None or date.fromisoformat(stats["last_final_block_on"]) > today:
        raise BadRequest("block_date_not_reached", f"La suspension annoncée n'est pas avant le {date.fromisoformat(stats['last_final_block_on']):%d/%m/%Y}.")
    s.status, s.blocked_at, s.blocked_reason = "blocked", clock.now(), data.reason.strip()
    db.add(SchoolNotice(school_id=s.id, kind="blocked", title="Accès suspendu", text=f"L'accès de l'établissement est suspendu pour impayé ({money(st['remaining'])}). Il sera rétabli dès le règlement.", created_by=admin.id))
    _audit(db, admin, s.id, "school.blocked", reason=data.reason.strip(), remaining=st["remaining"])
    await db.commit()
    return {"status": s.status}


@router.post("/schools/{school_id}/unblock")
async def unblock_school(school_id: int, admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> dict:
    await admin.require_recent_password()
    s = await _school(db, school_id)
    if s.status != "blocked":
        raise Conflict("not_blocked")
    s.status, s.blocked_at, s.blocked_reason = "active", None, None
    db.add(SchoolNotice(school_id=s.id, kind="unblocked", title="Accès rétabli", text="L'accès de l'établissement est rétabli. Merci.", created_by=admin.id))
    _audit(db, admin, s.id, "school.unblocked")
    await db.commit()
    return {"status": s.status}


@router.get("/audit")
async def audit(school_id: int | None = None, limit: int = 100, admin: AdminMe = Depends(current_admin), db: AsyncSession = Depends(get_session)) -> list[dict]:
    q = select(PlatformAudit).order_by(PlatformAudit.id.desc()).limit(min(max(limit, 1), 500))
    if school_id is not None:
        q = q.where(PlatformAudit.school_id == school_id)
    return [{"admin": a.admin, "school_id": a.school_id, "action": a.action, "detail": a.detail, "at": a.at.isoformat()} for a in await db.scalars(q)]
