"""Grades, report cards, conduct and attendance. Money is none of the teacher's business: these routes have their own role rules."""

from datetime import date, datetime

from fastapi import APIRouter, Depends
from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.deps import Me, current_me
from app.errors import BadRequest, Conflict, Forbidden, NotFound
from app.models import Absence, AcademicYear, AuditLog, Classroom, Coefficient, Enrollment, Evaluation, Grade, PeriodRemark, StaffMember, Student, Subject, TeacherAssignment
from app.schemas import AbsencesIn, ClassTeachersIn, CoefficientsIn, EvaluationIn, GradesIn, RemarkIn, SubjectIn
from app.services import academics

router = APIRouter(prefix="/v1", tags=["academics"])
ACADEMIC = ("director", "secretary", "teacher")


@router.get("/subjects")
async def subjects(classroom_id: int | None = None, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    """With `classroom_id`, only the subjects the caller may give in that class (a teacher: hers)."""
    m.require_role(*ACADEMIC)
    rows = [s for s in await db.scalars(select(Subject).where(Subject.school_id == m.school_id).order_by(Subject.name))]
    if classroom_id is not None:
        await academics.require_view(db, m.school_id, m.role, m.staff.id, classroom_id)
        _, _, allowed = await academics.teacher_scope(db, m.school_id, m.role, m.staff.id, classroom_id)
        if allowed is not None:
            rows = [s for s in rows if s.id in allowed]
    return [{"id": s.id, "name": s.name} for s in rows]


@router.post("/subjects", status_code=201)
async def add_subject(data: SubjectIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director")
    s = Subject(school_id=m.school_id, name=data.name.strip())
    db.add(s)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise Conflict("subject_exists") from None
    return {"id": s.id, "name": s.name}


@router.get("/coefficients")
async def coefficients(year_id: int, level: str, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    m.require_role(*ACADEMIC)
    rows = await db.scalars(select(Coefficient).where(Coefficient.school_id == m.school_id, Coefficient.year_id == year_id, Coefficient.level == level))
    return [{"subject_id": c.subject_id, "coef": c.coef} for c in rows]


@router.put("/coefficients")
async def set_coefficients(data: CoefficientsIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    m.require_role("director")
    if await db.scalar(select(AcademicYear.id).where(AcademicYear.id == data.year_id, AcademicYear.school_id == m.school_id)) is None:
        raise NotFound("year_not_found")
    mine = set((await db.scalars(select(Subject.id).where(Subject.school_id == m.school_id))).all())
    if any(line.subject_id not in mine for line in data.lines):
        raise NotFound("subject_not_found")
    await db.execute(delete(Coefficient).where(Coefficient.school_id == m.school_id, Coefficient.year_id == data.year_id, Coefficient.level == data.level))
    db.add_all([Coefficient(school_id=m.school_id, year_id=data.year_id, level=data.level, subject_id=ln.subject_id, coef=ln.coef) for ln in data.lines])
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="coefficients.replaced", entity="coefficient", detail={"level": data.level, "lines": len(data.lines)}))
    await db.commit()
    return [{"subject_id": ln.subject_id, "coef": ln.coef} for ln in data.lines]


def _eval(e: Evaluation) -> dict:
    return {"id": e.id, "classroom_id": e.classroom_id, "subject_id": e.subject_id, "period": e.period, "kind": e.kind, "title": e.title, "held_on": e.held_on.isoformat(),
            "max_score": e.max_score, "locked": e.locked_at is not None, "created_by": e.created_by}


@router.post("/evaluations", status_code=201)
async def add_evaluation(data: EvaluationIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*ACADEMIC)
    await academics.get_classroom(db, m.school_id, data.classroom_id)
    await academics.require_teach(db, m.school_id, m.role, m.staff.id, data.classroom_id, data.subject_id)
    if await db.scalar(select(Subject.id).where(Subject.id == data.subject_id, Subject.school_id == m.school_id)) is None:
        raise NotFound("subject_not_found")
    e = Evaluation(school_id=m.school_id, created_by=m.staff.id, held_on=data.held_on or date.today(), **data.model_dump(exclude={"held_on"}))
    db.add(e)
    await db.commit()
    return _eval(e)


@router.get("/evaluations")
async def evaluations(classroom_id: int, period: int | None = None, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    m.require_role(*ACADEMIC)
    await academics.require_view(db, m.school_id, m.role, m.staff.id, classroom_id)
    q = select(Evaluation).where(Evaluation.school_id == m.school_id, Evaluation.classroom_id == classroom_id).order_by(Evaluation.held_on.desc(), Evaluation.id.desc())
    if period:
        q = q.where(Evaluation.period == period)
    return [_eval(e) for e in await db.scalars(q)]


async def _editable(db: AsyncSession, m: Me, evaluation_id: int) -> Evaluation:
    ev = await db.scalar(select(Evaluation).where(Evaluation.id == evaluation_id, Evaluation.school_id == m.school_id))
    if ev is None:
        raise NotFound("evaluation_not_found")
    if m.role == "teacher":
        if ev.created_by != m.staff.id:
            raise Forbidden("not_your_evaluation")  # a teacher edits the marks of HER evaluations only
        await academics.require_teach(db, m.school_id, m.role, m.staff.id, ev.classroom_id, ev.subject_id)  # ...and only while still assigned
    return ev


@router.get("/evaluations/{evaluation_id}/grades")
async def get_grades(evaluation_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*ACADEMIC)
    ev = await db.scalar(select(Evaluation).where(Evaluation.id == evaluation_id, Evaluation.school_id == m.school_id))
    if ev is None:
        raise NotFound("evaluation_not_found")
    await academics.require_view(db, m.school_id, m.role, m.staff.id, ev.classroom_id)
    rows = (await db.execute(
        select(Enrollment, Student).join(Student, Student.id == Enrollment.student_id)
        .where(Enrollment.school_id == m.school_id, Enrollment.classroom_id == ev.classroom_id, Enrollment.status == "active").order_by(Student.last_name, Student.first_names)
    )).all()
    grades = {g.enrollment_id: g for g in await db.scalars(select(Grade).where(Grade.evaluation_id == ev.id))}
    return {"evaluation": _eval(ev), "rows": [
        {"enrollment_id": e.id, "name": f"{s.last_name} {s.first_names}", "value": str(grades[e.id].value) if e.id in grades and grades[e.id].value is not None else None,
         "absent": bool(e.id in grades and grades[e.id].absent)} for e, s in rows]}


@router.put("/evaluations/{evaluation_id}/grades")
async def put_grades(evaluation_id: int, data: GradesIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*ACADEMIC)
    ev = await _editable(db, m, evaluation_id)
    if ev.locked_at is not None:
        raise Conflict("evaluation_locked")
    ids = {g.enrollment_id for g in data.grades}
    valid = set((await db.scalars(select(Enrollment.id).where(Enrollment.school_id == m.school_id, Enrollment.classroom_id == ev.classroom_id, Enrollment.id.in_(ids)))).all())
    if ids - valid:
        raise BadRequest("student_not_in_class")
    for g in data.grades:
        if g.absent:
            value = None
        elif g.value is None:  # blank = not entered yet: remove any previous mark
            await db.execute(delete(Grade).where(Grade.evaluation_id == ev.id, Grade.enrollment_id == g.enrollment_id))
            continue
        else:
            if g.value > ev.max_score:
                raise BadRequest("grade_above_max", f"max {ev.max_score}")
            value = g.value
        stmt = pg_insert(Grade).values(school_id=m.school_id, evaluation_id=ev.id, enrollment_id=g.enrollment_id, value=value, absent=g.absent)
        await db.execute(stmt.on_conflict_do_update(index_elements=["evaluation_id", "enrollment_id"], set_={"value": value, "absent": g.absent}))
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="grades.saved", entity="evaluation", entity_id=ev.id, detail={"count": len(data.grades)}))
    await db.commit()
    return {"saved": len(data.grades)}


@router.post("/evaluations/{evaluation_id}/lock")
async def lock_evaluation(evaluation_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """Validation by the school's direction: after it, marks cannot be changed (a correction needs the director to unlock)."""
    m.require_role("director")
    ev = await _editable(db, m, evaluation_id)
    ev.locked_at = datetime.now().astimezone()
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="evaluation.locked", entity="evaluation", entity_id=ev.id))
    await db.commit()
    return _eval(ev)


@router.post("/evaluations/{evaluation_id}/unlock")
async def unlock_evaluation(evaluation_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director")
    ev = await _editable(db, m, evaluation_id)
    ev.locked_at = None
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="evaluation.unlocked", entity="evaluation", entity_id=ev.id))
    await db.commit()
    return _eval(ev)


@router.get("/classrooms/{classroom_id}/results")
async def results(classroom_id: int, period: int = 1, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*ACADEMIC)
    if period not in (0, 1, 2, 3):
        raise BadRequest("period_invalid")
    await academics.require_view(db, m.school_id, m.role, m.staff.id, classroom_id)
    return await academics.class_results(db, m.school_id, classroom_id, period)


@router.get("/enrollments/{enrollment_id}/report-card")
async def report_card(enrollment_id: int, period: int = 1, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*ACADEMIC)
    if period not in (0, 1, 2, 3):
        raise BadRequest("period_invalid")
    cls = await db.scalar(select(Enrollment.classroom_id).where(Enrollment.id == enrollment_id, Enrollment.school_id == m.school_id))
    if cls is None:
        raise NotFound("enrollment_not_found")
    await academics.require_view(db, m.school_id, m.role, m.staff.id, cls)
    return await academics.report_card(db, m.school_id, enrollment_id, period)


@router.put("/enrollments/{enrollment_id}/remarks")
async def put_remark(enrollment_id: int, data: RemarkIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """Conduct and appreciation: director, secretary, teacher. Sanction and the council's decision: the director only (a human decision)."""
    m.require_role(*ACADEMIC)
    if (data.sanction is not None or data.decision is not None) and m.role != "director":
        raise Forbidden("director_only")
    enr = await db.scalar(select(Enrollment).where(Enrollment.id == enrollment_id, Enrollment.school_id == m.school_id))
    if enr is None:
        raise NotFound("enrollment_not_found")
    await academics.require_head(db, m.school_id, m.role, m.staff.id, enr.classroom_id)
    row = await db.scalar(select(PeriodRemark).where(PeriodRemark.enrollment_id == enr.id, PeriodRemark.period == data.period))
    if row is None:
        row = PeriodRemark(school_id=m.school_id, enrollment_id=enr.id, period=data.period)
        db.add(row)
    for field in ("conduct", "appreciation"):
        if field in data.model_fields_set:
            setattr(row, field, getattr(data, field))
    if m.role == "director":
        for field in ("sanction", "decision"):
            if field in data.model_fields_set:
                setattr(row, field, getattr(data, field))
    await db.commit()
    return {"ok": True}


@router.post("/absences", status_code=201)
async def record_absences(data: AbsencesIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """The roll call of a day. Posting the same pupil and slot again updates it (justified, reason) instead of duplicating."""
    m.require_role(*ACADEMIC)
    ids = {e.enrollment_id for e in data.entries}
    found = dict((await db.execute(select(Enrollment.id, Enrollment.classroom_id).where(Enrollment.school_id == m.school_id, Enrollment.id.in_(ids)))).all()) if ids else {}
    if ids - set(found):
        raise BadRequest("student_not_found")
    for cid in set(found.values()) | ({data.classroom_id} if data.classroom_id else set()):
        await academics.require_view(db, m.school_id, m.role, m.staff.id, cid)
    if data.replace:
        if data.classroom_id is None:
            raise BadRequest("classroom_required")
        in_class = select(Enrollment.id).where(Enrollment.school_id == m.school_id, Enrollment.classroom_id == data.classroom_id)
        await db.execute(delete(Absence).where(Absence.school_id == m.school_id, Absence.day == data.day, Absence.enrollment_id.in_(in_class)))
    for e in data.entries:
        stmt = pg_insert(Absence).values(school_id=m.school_id, enrollment_id=e.enrollment_id, day=data.day, slot=e.slot, kind=e.kind, justified=e.justified, reason=e.reason, recorded_by=m.staff.id)
        await db.execute(stmt.on_conflict_do_update(index_elements=["enrollment_id", "day", "slot"], set_={"kind": e.kind, "justified": e.justified, "reason": e.reason}))
    await db.commit()
    return {"recorded": len(data.entries)}


@router.get("/classrooms/{classroom_id}/absences")
async def absences_of_day(classroom_id: int, day: date, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    m.require_role(*ACADEMIC)
    await academics.get_classroom(db, m.school_id, classroom_id)
    await academics.require_view(db, m.school_id, m.role, m.staff.id, classroom_id)
    rows = await db.execute(
        select(Absence, Student).join(Enrollment, Enrollment.id == Absence.enrollment_id).join(Student, Student.id == Enrollment.student_id)
        .where(Absence.school_id == m.school_id, Enrollment.classroom_id == classroom_id, Absence.day == day)
    )
    return [{"enrollment_id": a.enrollment_id, "name": f"{s.last_name} {s.first_names}", "kind": a.kind, "slot": a.slot, "justified": a.justified, "reason": a.reason} for a, s in rows.all()]


@router.get("/classrooms/{classroom_id}/teachers")
async def class_teachers(classroom_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director")
    room = await academics.get_classroom(db, m.school_id, classroom_id)
    rows = (await db.execute(
        select(TeacherAssignment, StaffMember).join(StaffMember, StaffMember.id == TeacherAssignment.staff_id)
        .where(TeacherAssignment.school_id == m.school_id, TeacherAssignment.classroom_id == room.id).order_by(StaffMember.display_name, TeacherAssignment.id)
    )).all()
    return {"head_teacher_id": room.head_teacher_id, "assignments": [{"staff_id": a.staff_id, "name": s.display_name, "subject_id": a.subject_id} for a, s in rows]}


@router.put("/classrooms/{classroom_id}/teachers")
async def set_class_teachers(classroom_id: int, data: ClassTeachersIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """The director says who teaches what in this class (replaces the list) and who is its head teacher."""
    m.require_role("director")
    room = await academics.get_classroom(db, m.school_id, classroom_id)
    teacher_ids = set((await db.scalars(select(StaffMember.id).where(StaffMember.school_id == m.school_id, StaffMember.role == "teacher", StaffMember.active))).all())
    subject_ids = set((await db.scalars(select(Subject.id).where(Subject.school_id == m.school_id))).all())
    wanted = {(a.staff_id, a.subject_id) for a in data.assignments}
    if any(sid not in teacher_ids for sid, _ in wanted) or (data.head_teacher_id is not None and data.head_teacher_id not in teacher_ids):
        raise BadRequest("not_an_active_teacher")
    if any(sub is not None and sub not in subject_ids for _, sub in wanted):
        raise NotFound("subject_not_found")
    await db.execute(delete(TeacherAssignment).where(TeacherAssignment.school_id == m.school_id, TeacherAssignment.classroom_id == room.id))
    db.add_all([TeacherAssignment(school_id=m.school_id, staff_id=sid, classroom_id=room.id, subject_id=sub) for sid, sub in sorted(wanted, key=lambda t: (t[0], t[1] or 0))])
    room.head_teacher_id = data.head_teacher_id
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="class.teachers.set", entity="classroom", entity_id=room.id, detail={"assignments": len(wanted), "head": data.head_teacher_id}))
    await db.commit()
    return {"ok": True, "assignments": len(wanted)}
