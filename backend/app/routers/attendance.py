"""Attendance during a COURSE (the teacher calls the roll of her period), and what parents told the school about a day."""

from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.db import get_session
from app.deps import Me, current_me
from app.errors import BadRequest, Forbidden, NotFound
from app.models import Absence, AbsenceReport, AuditLog, Classroom, Enrollment, SlotCancellation, Student, Subject, TimetableSlot
from app.schemas import CourseRollIn
from app.services import academics, attendance

router = APIRouter(prefix="/v1", tags=["attendance"])
ROLL_ROLES = ("director", "secretary", "teacher")


async def _slot_for_roll(db: AsyncSession, m: Me, slot_id: int, day: date) -> tuple[TimetableSlot, SlotCancellation | None]:
    """Who may call the roll of this period on this day: the teacher of the period, the replacement teacher assigned for that session, the director and the secretary."""
    m.require_role(*ROLL_ROLES)
    slot = await db.scalar(select(TimetableSlot).where(TimetableSlot.id == slot_id, TimetableSlot.school_id == m.school_id))
    if slot is None:
        raise NotFound("slot_not_found")
    if day.isoweekday() != slot.weekday:
        raise BadRequest("date_not_that_weekday", "Ce cours n'a pas lieu ce jour-là.")
    today = clock.now().date()
    if day > today:
        raise BadRequest("date_in_the_future", "On ne peut pas faire l'appel d'un cours qui n'a pas encore eu lieu.")
    cancelled = await db.scalar(select(SlotCancellation).where(SlotCancellation.slot_id == slot.id, SlotCancellation.on_date == day))
    if m.role == "teacher":
        substitute = cancelled is not None and cancelled.substitute_staff_id == m.staff.id
        if slot.teacher_id != m.staff.id and not substitute:
            raise Forbidden("not_your_course")
        if day != today:
            raise BadRequest("only_today", "Vous pouvez faire l'appel d'aujourd'hui seulement ; demandez à la direction pour un autre jour.")
        if cancelled is not None and not substitute:
            raise BadRequest("session_cancelled", "Ce cours est annulé.")
    else:
        if day < today - timedelta(days=30):
            raise BadRequest("date_too_old", "Cette date est trop ancienne.")
        if cancelled is not None and cancelled.substitute_staff_id is None:
            raise BadRequest("session_cancelled", "Ce cours est annulé.")
    return slot, cancelled


async def _roster(db: AsyncSession, school_id: int, classroom_id: int):
    return (await db.execute(
        select(Enrollment.id, Student).join(Student, Student.id == Enrollment.student_id)
        .where(Enrollment.school_id == school_id, Enrollment.classroom_id == classroom_id, Enrollment.status == "active").order_by(Student.last_name, Student.first_names)
    )).all()


@router.get("/timetable/slots/{slot_id}/roll")
async def course_roll(slot_id: int, on_date: date, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    slot, _ = await _slot_for_roll(db, m, slot_id, on_date)
    roster = await _roster(db, m.school_id, slot.classroom_id)
    ids = [r[0] for r in roster]
    course = {a.enrollment_id: a for a in await db.scalars(select(Absence).where(Absence.slot_id == slot.id, Absence.day == on_date))}
    whole_day = set((await db.scalars(select(Absence.enrollment_id).where(Absence.slot_id.is_(None), Absence.day == on_date, Absence.kind == "absence", Absence.enrollment_id.in_(ids or [-1])))).all())
    reported = {r.enrollment_id: r for r in await db.scalars(select(AbsenceReport).where(AbsenceReport.day == on_date, AbsenceReport.enrollment_id.in_(ids or [-1])))}
    return {"rows": [{
        "enrollment_id": eid, "name": f"{st.last_name} {st.first_names}", "status": course[eid].kind if eid in course else "present", "justified": bool(eid in course and course[eid].justified),
        "absent_all_day": eid in whole_day, "reported": ({"reason": reported[eid].reason, "note": reported[eid].note} if eid in reported else None)} for eid, st in roster]}


@router.put("/timetable/slots/{slot_id}/roll")
async def save_course_roll(slot_id: int, data: CourseRollIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """The roll of one period: the list of pupils who are NOT present. It REPLACES what was noted for that period and day. Each new absence or lateness
    tells the parent the same day (opt-in only)."""
    slot, _ = await _slot_for_roll(db, m, slot_id, data.on_date)
    roster = {eid for eid, _ in await _roster(db, m.school_id, slot.classroom_id)}
    if any(e.enrollment_id not in roster for e in data.entries):
        raise BadRequest("student_not_in_class")
    before = {a.enrollment_id: a.kind for a in await db.scalars(select(Absence).where(Absence.slot_id == slot.id, Absence.day == data.on_date))}
    await db.execute(delete(Absence).where(Absence.slot_id == slot.id, Absence.day == data.on_date))
    for e in data.entries:
        await db.execute(pg_insert(Absence).values(school_id=m.school_id, enrollment_id=e.enrollment_id, day=data.on_date, slot="cours", slot_id=slot.id, kind=e.kind, justified=e.justified, reason=e.reason, recorded_by=m.staff.id)
                         .on_conflict_do_nothing())
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="course.roll.saved", entity="timetable_slot", entity_id=slot.id, detail={"date": data.on_date.isoformat(), "absent": len(data.entries)}))
    await db.commit()
    subject = await db.scalar(select(Subject.name).where(Subject.id == slot.subject_id))
    where = f"au cours de {subject} ({slot.start_time.strftime('%H:%M')}-{slot.end_time.strftime('%H:%M')})"
    notified = 0
    now = clock.now()
    for e in data.entries:
        if before.get(e.enrollment_id) == e.kind:
            continue  # already noted that way: the parent has been told
        notified += int(await attendance.notify(db, school_id=m.school_id, enrollment_id=e.enrollment_id, kind=e.kind, day=data.on_date, where=where, key=f"s{slot.id}", now=now))
    await db.commit()
    return {"recorded": len(data.entries), "notified": notified}


@router.get("/classrooms/{classroom_id}/absence-reports")
async def class_reports(classroom_id: int, day: date, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    """What parents told the school about this day, for one class (the roll call shows it next to the pupil)."""
    m.require_role(*ROLL_ROLES)
    await academics.get_classroom(db, m.school_id, classroom_id)
    await academics.require_view(db, m.school_id, m.role, m.staff.id, classroom_id)
    rows = (await db.execute(
        select(AbsenceReport, Student).join(Enrollment, Enrollment.id == AbsenceReport.enrollment_id).join(Student, Student.id == Enrollment.student_id)
        .where(AbsenceReport.school_id == m.school_id, Enrollment.classroom_id == classroom_id, AbsenceReport.day == day).order_by(Student.last_name)
    )).all()
    return [{"enrollment_id": r.enrollment_id, "name": f"{s.last_name} {s.first_names}", "reason": r.reason, "note": r.note} for r, s in rows]


@router.get("/absence-reports")
async def school_reports(day: date | None = None, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    """For the director and the secretary: every absence a parent has reported for a day (today by default), by class."""
    m.require_role("director", "secretary")
    day = day or clock.now().date()
    rows = (await db.execute(
        select(AbsenceReport, Student, Classroom.name).join(Enrollment, Enrollment.id == AbsenceReport.enrollment_id).join(Student, Student.id == Enrollment.student_id)
        .join(Classroom, Classroom.id == Enrollment.classroom_id).where(AbsenceReport.school_id == m.school_id, AbsenceReport.day == day).order_by(Classroom.name, Student.last_name)
    )).all()
    return [{"enrollment_id": r.enrollment_id, "name": f"{s.last_name} {s.first_names}", "classroom": cname, "reason": r.reason, "note": r.note, "day": r.day.isoformat()} for r, s, cname in rows]
