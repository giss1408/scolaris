"""The weekly timetable. Built by the director or the secretary; read by the teachers (their own week and their classes) and by parents (their child's class).

Three things can never overlap on one weekday: two periods of the same class, two periods of the same teacher (in any class), two periods in the same room."""

from datetime import date, timedelta, time

from fastapi import APIRouter, Depends
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.db import get_session
from app.deps import Me, current_me
from app.errors import BadRequest, Conflict, Forbidden, NotFound
from app.models import AcademicYear, AuditLog, Classroom, SlotCancellation, StaffMember, Subject, TeacherAssignment, TimetableSlot
from app.schemas import CancelIn, SlotIn
from app.services import academics

router = APIRouter(prefix="/v1", tags=["timetable"])
EDITORS = ("director", "secretary")
READERS = ("director", "secretary", "teacher")
DAYS = {1: "Lundi", 2: "Mardi", 3: "Mercredi", 4: "Jeudi", 5: "Vendredi", 6: "Samedi"}


def hhmm(t: time) -> str:
    return t.strftime("%H:%M")


async def slots_json(db: AsyncSession, school_id: int, where) -> list[dict]:
    """Slots with the names the screens need (class, subject, teacher), ordered by day then start."""
    rows = (await db.execute(
        select(TimetableSlot, Classroom.name, Subject.name, StaffMember.display_name)
        .join(Classroom, Classroom.id == TimetableSlot.classroom_id).join(Subject, Subject.id == TimetableSlot.subject_id)
        .outerjoin(StaffMember, StaffMember.id == TimetableSlot.teacher_id)
        .where(TimetableSlot.school_id == school_id, where).order_by(TimetableSlot.weekday, TimetableSlot.start_time, TimetableSlot.id)
    )).all()
    return [{"id": s.id, "classroom_id": s.classroom_id, "classroom": cname, "weekday": s.weekday, "start": hhmm(s.start_time), "end": hhmm(s.end_time),
             "subject_id": s.subject_id, "subject": sname, "teacher_id": s.teacher_id, "teacher": tname, "room": s.room} for s, cname, sname, tname in rows]


async def cancellations_json(db: AsyncSession, school_id: int, where, *, viewer_role: str | None, viewer_staff_id: int | None = None) -> list[dict]:
    """Upcoming (and yesterday's) cancelled sessions of the selected periods.

    The reason is private: a teacher's illness is her own business. It is shown to the administration (director, secretary) and to the
    teacher of that period, never to a colleague reading the class timetable and never to parents (`viewer_role=None`)."""
    today = clock.now().date()
    rows = (await db.execute(
        select(SlotCancellation, TimetableSlot.teacher_id).join(TimetableSlot, TimetableSlot.id == SlotCancellation.slot_id)
        .where(SlotCancellation.school_id == school_id, SlotCancellation.on_date >= today - timedelta(days=1), SlotCancellation.on_date <= today + timedelta(days=28), where)
        .order_by(SlotCancellation.on_date)
    )).all()
    out = []
    for c, teacher_id in rows:
        item = {"slot_id": c.slot_id, "date": c.on_date.isoformat()}
        if viewer_role in EDITORS or (viewer_role == "teacher" and teacher_id is not None and teacher_id == viewer_staff_id):
            item.update(reason=c.reason, note=c.note)
        out.append(item)
    return out


@router.get("/classrooms/{classroom_id}/timetable")
async def class_timetable(classroom_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*READERS)
    room = await academics.get_classroom(db, m.school_id, classroom_id)
    await academics.require_view(db, m.school_id, m.role, m.staff.id, classroom_id)
    out: dict = {"classroom": {"id": room.id, "name": room.name}, "editable": m.role in EDITORS, "slots": await slots_json(db, m.school_id, TimetableSlot.classroom_id == room.id),
                 "cancellations": await cancellations_json(db, m.school_id, TimetableSlot.classroom_id == room.id, viewer_role=m.role, viewer_staff_id=m.staff.id)}
    if m.role in EDITORS:
        # who may be put in a period of this class, and for which subjects (None = all): the assigned teachers only
        rows = (await db.execute(
            select(TeacherAssignment.staff_id, TeacherAssignment.subject_id, StaffMember.display_name).join(StaffMember, StaffMember.id == TeacherAssignment.staff_id)
            .where(TeacherAssignment.school_id == m.school_id, TeacherAssignment.classroom_id == room.id, StaffMember.active)
        )).all()
        teachers: dict[int, dict] = {}
        for sid, sub, name in rows:
            t = teachers.setdefault(sid, {"id": sid, "name": name, "subject_ids": []})
            if sub is None or t["subject_ids"] is None:
                t["subject_ids"] = None
            else:
                t["subject_ids"].append(sub)
        out["teachers"] = list(teachers.values())
    return out


async def _clash(db: AsyncSession, school_id: int, data: SlotIn, classroom_id: int) -> None:
    def overlap(*extra):
        return select(TimetableSlot, Classroom.name).join(Classroom, Classroom.id == TimetableSlot.classroom_id).where(
            TimetableSlot.school_id == school_id, TimetableSlot.weekday == data.weekday, TimetableSlot.start_time < data.end, TimetableSlot.end_time > data.start, *extra).limit(1)

    hit = (await db.execute(overlap(TimetableSlot.classroom_id == classroom_id))).first()
    if hit:
        raise Conflict("class_overlap", f"Cette classe a déjà un cours de {hhmm(hit[0].start_time)} à {hhmm(hit[0].end_time)}.")
    if data.teacher_id is not None:
        hit = (await db.execute(overlap(TimetableSlot.teacher_id == data.teacher_id))).first()
        if hit:
            raise Conflict("teacher_busy", f"L'enseignant(e) est déjà en {hit[1]} de {hhmm(hit[0].start_time)} à {hhmm(hit[0].end_time)}.")
    room = (data.room or "").strip()
    if room:
        hit = (await db.execute(overlap(func.lower(TimetableSlot.room) == room.lower()))).first()
        if hit:
            raise Conflict("room_busy", f"La salle {room} est déjà prise par la {hit[1]} de {hhmm(hit[0].start_time)} à {hhmm(hit[0].end_time)}.")


@router.post("/classrooms/{classroom_id}/timetable/slots", status_code=201)
async def add_slot(classroom_id: int, data: SlotIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*EDITORS)
    room = await academics.get_classroom(db, m.school_id, classroom_id)
    if data.end <= data.start:
        raise BadRequest("end_before_start", "L'heure de fin doit être après l'heure de début.")
    if await db.scalar(select(Subject.id).where(Subject.id == data.subject_id, Subject.school_id == m.school_id)) is None:
        raise NotFound("subject_not_found")
    if data.teacher_id is not None:
        # only a teacher the director assigned to THIS class, for THIS subject (or all her subjects there)
        ok = await db.scalar(
            select(TeacherAssignment.id).join(StaffMember, StaffMember.id == TeacherAssignment.staff_id).where(
                TeacherAssignment.school_id == m.school_id, TeacherAssignment.classroom_id == room.id, TeacherAssignment.staff_id == data.teacher_id, StaffMember.active,
                or_(TeacherAssignment.subject_id.is_(None), TeacherAssignment.subject_id == data.subject_id)).limit(1))
        if ok is None:
            raise BadRequest("teacher_not_assigned", "Cet enseignant n'est pas affecté à cette classe pour cette matière.")
    await _clash(db, m.school_id, data, room.id)
    slot = TimetableSlot(school_id=m.school_id, classroom_id=room.id, weekday=data.weekday, start_time=data.start, end_time=data.end, subject_id=data.subject_id,
                         teacher_id=data.teacher_id, room=(data.room or "").strip() or None)
    db.add(slot)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="timetable.slot.added", entity="classroom", entity_id=room.id, detail={"weekday": data.weekday, "start": hhmm(data.start)}))
    await db.commit()
    return (await slots_json(db, m.school_id, TimetableSlot.id == slot.id))[0]


@router.delete("/timetable/slots/{slot_id}")
async def delete_slot(slot_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*EDITORS)
    slot = await db.scalar(select(TimetableSlot).where(TimetableSlot.id == slot_id, TimetableSlot.school_id == m.school_id))
    if slot is None:
        raise NotFound("slot_not_found")
    await db.delete(slot)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="timetable.slot.removed", entity="classroom", entity_id=slot.classroom_id))
    await db.commit()
    return {"ok": True}


@router.get("/timetable/me")
async def my_week(staff_id: int | None = None, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """A teacher's week across all her classes. A teacher reads her own; the director and secretary can read any teacher's with `staff_id`."""
    m.require_role(*READERS)
    if m.role == "teacher":
        target = m.staff.id
    else:
        if staff_id is None:
            raise BadRequest("staff_id_required")
        target = staff_id
        if await db.scalar(select(StaffMember.id).where(StaffMember.id == target, StaffMember.school_id == m.school_id)) is None:
            raise NotFound("staff_not_found")
    return {"slots": await slots_json(db, m.school_id, TimetableSlot.teacher_id == target),
            "cancellations": await cancellations_json(db, m.school_id, TimetableSlot.teacher_id == target, viewer_role=m.role, viewer_staff_id=m.staff.id)}


async def _own_slot(db: AsyncSession, m: Me, slot_id: int) -> TimetableSlot:
    slot = await db.scalar(select(TimetableSlot).where(TimetableSlot.id == slot_id, TimetableSlot.school_id == m.school_id))
    if slot is None:
        raise NotFound("slot_not_found")
    if m.role == "teacher" and slot.teacher_id != m.staff.id:
        raise Forbidden("not_your_course")  # a teacher cancels HER sessions only
    return slot


@router.post("/timetable/slots/{slot_id}/cancellations", status_code=201)
async def cancel_session(slot_id: int, data: CancelIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """Cancel one session (a date) of a period, with a reason. The teacher of the period, the director or the secretary can."""
    m.require_role(*READERS)
    slot = await _own_slot(db, m, slot_id)
    now = clock.now()
    if data.on_date.isoweekday() != slot.weekday:
        raise BadRequest("date_not_that_weekday", f"Ce cours a lieu le {DAYS[slot.weekday].lower()}.")
    if data.on_date < now.date():
        raise BadRequest("date_in_the_past", "Cette date est passée.")
    if data.on_date == now.date() and slot.end_time <= now.time():
        raise BadRequest("course_already_over", "Ce cours est déjà terminé.")
    room = await db.get(Classroom, slot.classroom_id)
    year = await db.get(AcademicYear, room.year_id)
    if not (year.starts_on <= data.on_date <= year.ends_on):
        raise BadRequest("outside_school_year", "Cette date est hors de l'année scolaire.")
    note = (data.note or "").strip() or None
    if data.reason == "autre" and (note is None or len(note) < 3):
        raise BadRequest("note_required", "Précisez le motif.")
    if await db.scalar(select(SlotCancellation.id).where(SlotCancellation.slot_id == slot.id, SlotCancellation.on_date == data.on_date)):
        raise Conflict("session_already_cancelled", "Cette séance est déjà annulée.")
    c = SlotCancellation(school_id=m.school_id, slot_id=slot.id, on_date=data.on_date, reason=data.reason, note=note, cancelled_by=m.staff.id)
    db.add(c)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="timetable.session.cancelled", entity="timetable_slot", entity_id=slot.id, detail={"date": data.on_date.isoformat(), "reason": data.reason}))
    await db.commit()
    return {"slot_id": slot.id, "date": data.on_date.isoformat(), "reason": c.reason, "note": c.note}


@router.delete("/timetable/slots/{slot_id}/cancellations/{day}")
async def restore_session(slot_id: int, day: date, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """Undo a cancellation (the teacher is better, the course takes place). Only while the day has not passed."""
    m.require_role(*READERS)
    slot = await _own_slot(db, m, slot_id)
    if day < clock.now().date():
        raise BadRequest("date_in_the_past", "Cette date est passée.")
    c = await db.scalar(select(SlotCancellation).where(SlotCancellation.slot_id == slot.id, SlotCancellation.on_date == day))
    if c is None:
        raise NotFound("cancellation_not_found")
    await db.delete(c)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="timetable.session.restored", entity="timetable_slot", entity_id=slot.id, detail={"date": day.isoformat()}))
    await db.commit()
    return {"ok": True}


@router.get("/timetable/cancellations")
async def upcoming_cancellations(days: int = 30, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    """For the administration: the sessions cancelled from today on, with the real reason and a ready message for the families
    (it says "enseignant absent": the reason itself stays inside the school)."""
    m.require_role(*EDITORS)
    today = clock.now().date()
    rows = (await db.execute(
        select(SlotCancellation, TimetableSlot, Classroom.name, Subject.name, StaffMember.display_name)
        .join(TimetableSlot, TimetableSlot.id == SlotCancellation.slot_id).join(Classroom, Classroom.id == TimetableSlot.classroom_id)
        .join(Subject, Subject.id == TimetableSlot.subject_id).outerjoin(StaffMember, StaffMember.id == TimetableSlot.teacher_id)
        .where(SlotCancellation.school_id == m.school_id, SlotCancellation.on_date >= today, SlotCancellation.on_date <= today + timedelta(days=min(max(days, 1), 120)))
        .order_by(SlotCancellation.on_date, TimetableSlot.start_time)
    )).all()
    out = []
    for c, s, cname, sname, tname in rows:
        out.append({
            "slot_id": s.id, "date": c.on_date.isoformat(), "weekday": s.weekday, "start": hhmm(s.start_time), "end": hhmm(s.end_time), "classroom": cname, "subject": sname, "teacher": tname,
            "reason": c.reason, "note": c.note,
            "message": f"Le cours de {sname} de la {cname} du {DAYS[s.weekday].lower()} {c.on_date.strftime('%d/%m')} ({hhmm(s.start_time)}-{hhmm(s.end_time)}) est annulé (enseignant absent). Merci de votre compréhension.",
        })
    return out
