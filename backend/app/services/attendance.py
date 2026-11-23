"""Telling parents their child was marked absent or late, the day it happens (one message per notice, only with opt-in)."""

from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AbsenceReport, Enrollment, Student
from app.services import outbox


async def notify(db: AsyncSession, *, school_id: int, enrollment_id: int, kind: str, day: date, where: str, key: str, now: datetime) -> bool:
    """Queue the notice for the family. A parent who already reported the absence for that day is not told what she told us."""
    if kind == "absence" and await db.scalar(select(AbsenceReport.id).where(AbsenceReport.enrollment_id == enrollment_id, AbsenceReport.day == day)):
        return False
    enr = await db.get(Enrollment, enrollment_id)
    st = await db.get(Student, enr.student_id)
    what = "absent(e)" if kind == "absence" else "en retard"
    text = f"{st.first_names} {st.last_name} a été noté(e) {what} {where} le {day.strftime('%d/%m')}."
    msg = await outbox.enqueue(db, school_id=school_id, family_id=st.family_id, kind="absence", text=text, dedupe_key=f"absence:{enrollment_id}:{day.isoformat()}:{key}:{kind}", now=now)
    return msg is not None
