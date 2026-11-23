"""The weekly timetable. Built by the director or the secretary; read by the teachers (their own week and their classes) and by parents (their child's class).

Three things can never overlap on one weekday: two periods of the same class, two periods of the same teacher (in any class), two periods in the same room."""

from datetime import time

from fastapi import APIRouter, Depends
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.deps import Me, current_me
from app.errors import BadRequest, Conflict, NotFound
from app.models import AuditLog, Classroom, StaffMember, Subject, TeacherAssignment, TimetableSlot
from app.schemas import SlotIn
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


@router.get("/classrooms/{classroom_id}/timetable")
async def class_timetable(classroom_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*READERS)
    room = await academics.get_classroom(db, m.school_id, classroom_id)
    await academics.require_view(db, m.school_id, m.role, m.staff.id, classroom_id)
    out: dict = {"classroom": {"id": room.id, "name": room.name}, "editable": m.role in EDITORS, "slots": await slots_json(db, m.school_id, TimetableSlot.classroom_id == room.id)}
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
    return {"slots": await slots_json(db, m.school_id, TimetableSlot.teacher_id == target)}
