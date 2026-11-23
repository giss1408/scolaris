"""Telling the families of a class that a session is cancelled, or who replaces the teacher. One message per family, only with opt-in (see outbox)."""

from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Enrollment, Student, Subject, TimetableSlot
from app.services import outbox

DAYS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]


async def notify_session(db: AsyncSession, *, school_id: int, slot: TimetableSlot, day: date, substitute_name: str | None, now: datetime) -> int:
    """Cancelled (teacher absent), with the replacement when there is one. Re-sent when a replacement is named later (another key)."""
    subject = await db.scalar(select(Subject.name).where(Subject.id == slot.subject_id))
    when = f"{DAYS[day.weekday()]} {day.strftime('%d/%m')} ({slot.start_time.strftime('%H:%M')}-{slot.end_time.strftime('%H:%M')})"
    if substitute_name:
        text = f"Le cours de {subject} du {when} n'est pas assuré par son enseignant habituel : il sera tenu par {substitute_name}."
        key = f"substitute:{slot.id}:{day.isoformat()}:{substitute_name}"
    else:
        text = f"Le cours de {subject} du {when} est annulé (enseignant absent)."
        key = f"cancel:{slot.id}:{day.isoformat()}"
    families = (await db.scalars(
        select(Student.family_id).join(Enrollment, Enrollment.student_id == Student.id)
        .where(Enrollment.school_id == school_id, Enrollment.classroom_id == slot.classroom_id, Enrollment.status == "active").distinct()
    )).all()
    n = 0
    for fid in families:
        n += int(await outbox.enqueue(db, school_id=school_id, family_id=fid, kind="cancellation" if not substitute_name else "substitute", text=text, dedupe_key=f"{key}:f{fid}", now=now) is not None)
    return n
