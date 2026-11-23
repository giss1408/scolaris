"""Reminders of late payments (see services/reminders.py), promises to pay, and what they recovered."""

from datetime import date

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.db import get_session
from app.deps import Me, current_me
from app.errors import NotFound
from app.models import AuditLog, Enrollment, Family, Payment, PaymentPromise, Reminder, Student
from app.services import reminders

router = APIRouter(prefix="/v1", tags=["reminders"])


class PromiseIn(BaseModel):
    amount: int = Field(gt=0, le=100_000_000)
    promised_for: date


@router.get("/reminders")
async def due_reminders(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """Plans what is due today (idempotent) and lists the messages waiting for a person to send them."""
    m.require_role("director", "accountant")
    now = clock.now()
    from app.models import AcademicYear

    year = await db.scalar(select(AcademicYear).where(AcademicYear.school_id == m.school_id, AcademicYear.is_current))
    if year is None:
        return {"planned": 0, "items": []}
    stats = await reminders.plan(db, m.school_id, year.id, now)
    return {**stats, "items": await reminders.due_list(db, m.school_id, now, include_direction=m.role == "director")}


@router.post("/reminders/{reminder_id}/sent")
async def sent(reminder_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "accountant")
    r = await db.scalar(select(Reminder).where(Reminder.id == reminder_id, Reminder.school_id == m.school_id))
    if r is None or (r.channel == "direction" and m.role != "director"):
        raise NotFound("reminder_not_found")
    changed = await reminders.mark_sent(db, m.school_id, reminder_id, m.staff.id, clock.now())
    return {"ok": True, "changed": changed}


@router.post("/reminders/{reminder_id}/skip")
async def skip(reminder_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "accountant")
    r = await db.scalar(select(Reminder).where(Reminder.id == reminder_id, Reminder.school_id == m.school_id))
    if r is None or (r.channel == "direction" and m.role != "director"):
        raise NotFound("reminder_not_found")
    if r.status == "planned":
        r.status = "skipped"
        await db.commit()
    return {"ok": True}


@router.post("/families/{family_id}/promises", status_code=201)
async def promise(family_id: int, data: PromiseIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """"I will pay on the 15th": reminders to this family pause until that date."""
    m.require_role("director", "accountant")
    if await db.scalar(select(Family.id).where(Family.id == family_id, Family.school_id == m.school_id)) is None:
        raise NotFound("family_not_found")
    p = PaymentPromise(school_id=m.school_id, family_id=family_id, amount=data.amount, promised_for=data.promised_for, recorded_by=m.staff.id)
    db.add(p)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="promise.recorded", entity="family", entity_id=family_id, detail={"amount": data.amount, "for": data.promised_for.isoformat()}))
    await db.commit()
    return {"id": p.id, "promised_for": p.promised_for.isoformat(), "amount": p.amount}


@router.get("/reminders/summary")
async def summary(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """Follow-up: reminders sent, and what those families paid AFTER their first reminder."""
    m.require_role("director", "accountant")
    first = (await db.execute(
        select(Reminder.family_id, func.min(Reminder.sent_at)).where(Reminder.school_id == m.school_id, Reminder.status == "sent", Reminder.channel != "direction").group_by(Reminder.family_id)
    )).all()
    recovered = 0
    for fid, at in first:
        recovered += int(await db.scalar(
            select(func.coalesce(func.sum(Payment.amount), 0)).join(Enrollment, Enrollment.id == Payment.enrollment_id).join(Student, Student.id == Enrollment.student_id)
            .where(Payment.school_id == m.school_id, Student.family_id == fid, Payment.paid_at > at)
        ) or 0)
    sent_n = int(await db.scalar(select(func.count()).select_from(Reminder).where(Reminder.school_id == m.school_id, Reminder.status == "sent")) or 0)
    return {"sent": sent_n, "families_reminded": len(first), "recovered_after_reminder": recovered}
