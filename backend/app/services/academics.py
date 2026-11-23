"""Class results and report cards for one school (every query filtered by school_id)."""

from collections import defaultdict
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import NotFound
from app.models import Absence, Classroom, Coefficient, Enrollment, Evaluation, Grade, PeriodRemark, School, Student, Subject
from app.services.grades import Rank, annual_average, honour, passes, period_average, rank_all, subject_average


async def get_classroom(db: AsyncSession, school_id: int, classroom_id: int) -> Classroom:
    room = await db.scalar(select(Classroom).where(Classroom.id == classroom_id, Classroom.school_id == school_id))
    if room is None:
        raise NotFound("classroom_not_found")
    return room


async def _period_table(db: AsyncSession, school_id: int, room: Classroom, enrollments: list[Enrollment], period: int, subjects: dict[int, Subject], coefs: dict[int, int]) -> dict[int, dict[int, Decimal | None]]:
    """enrolment id -> subject id -> average, for one period."""
    evals = list((await db.scalars(select(Evaluation).where(Evaluation.school_id == school_id, Evaluation.classroom_id == room.id, Evaluation.period == period))).all())
    by_eval = {e.id: e for e in evals}
    grades = list((await db.scalars(select(Grade).where(Grade.school_id == school_id, Grade.evaluation_id.in_(list(by_eval))))).all()) if by_eval else []
    bucket: dict[tuple[int, int], list] = defaultdict(list)
    for g in grades:
        ev = by_eval[g.evaluation_id]
        bucket[(g.enrollment_id, ev.subject_id)].append((g.value, ev.max_score, g.absent))
    return {e.id: {sid: subject_average(bucket.get((e.id, sid), [])) for sid in subjects} for e in enrollments}


async def class_results(db: AsyncSession, school_id: int, classroom_id: int, period: int) -> dict:
    """period 1..3, or 0 for the year (mean of the period averages)."""
    room = await get_classroom(db, school_id, classroom_id)
    enrollments = list((await db.scalars(select(Enrollment).where(Enrollment.school_id == school_id, Enrollment.classroom_id == room.id, Enrollment.status == "active"))).all())
    students = {s.id: s for s in (await db.scalars(select(Student).where(Student.id.in_([e.student_id for e in enrollments])))).all()} if enrollments else {}
    subjects = {s.id: s for s in (await db.scalars(select(Subject).where(Subject.school_id == school_id).order_by(Subject.name))).all()}
    coefs = {c.subject_id: c.coef for c in (await db.scalars(select(Coefficient).where(Coefficient.school_id == school_id, Coefficient.year_id == room.year_id, Coefficient.level == room.level))).all()}
    school = await db.get(School, school_id)

    periods = [period] if period else [1, 2, 3]
    per_period: dict[int, dict[int, dict[int, Decimal | None]]] = {}
    per_avg: dict[int, dict[int, Decimal | None]] = {}
    for p in periods:
        table = await _period_table(db, school_id, room, enrollments, p, subjects, coefs)
        per_period[p] = table
        per_avg[p] = {eid: period_average(row, coefs) for eid, row in table.items()}
    if period:
        shown = per_period[period]
        averages = per_avg[period]
    else:
        shown = {e.id: {sid: annual_average([per_period[p][e.id][sid] for p in periods]) for sid in subjects} for e in enrollments}
        averages = {e.id: annual_average([per_avg[p][e.id] for p in periods]) for e in enrollments}
    ranks: dict[int, Rank] = rank_all(averages)

    rows = []
    for e in sorted(enrollments, key=lambda e: (students[e.student_id].last_name, students[e.student_id].first_names)):
        st = students[e.student_id]
        r = ranks.get(e.id)
        rows.append({
            "enrollment_id": e.id, "student_id": st.id, "name": f"{st.last_name} {st.first_names}",
            "subjects": {str(sid): (str(v) if v is not None else None) for sid, v in shown[e.id].items()},
            "average": str(averages[e.id]) if averages[e.id] is not None else None,
            "rank": {"position": r.position, "tie": r.tie, "of": r.of} if r else None,
            "honour": honour(averages[e.id], school.honour_thresholds), "passes": passes(averages[e.id]),
        })
    class_avg = {}
    for sid in subjects:
        vals = [shown[e.id][sid] for e in enrollments if shown[e.id][sid] is not None]
        class_avg[str(sid)] = str(sum(vals) / len(vals)) if vals else None
    valid = [a for a in averages.values() if a is not None]
    return {
        "classroom": {"id": room.id, "name": room.name, "level": room.level}, "period": period,
        "subjects": [{"id": s.id, "name": s.name, "coef": coefs.get(s.id, 0)} for s in subjects.values()],
        "rows": rows, "subject_class_average": class_avg,
        "class_average": str(round(sum(valid) / len(valid), 2)) if valid else None,
        "highest": str(max(valid)) if valid else None, "lowest": str(min(valid)) if valid else None,
    }


async def report_card(db: AsyncSession, school_id: int, enrollment_id: int, period: int) -> dict:
    enr = await db.scalar(select(Enrollment).where(Enrollment.id == enrollment_id, Enrollment.school_id == school_id))
    if enr is None:
        raise NotFound("enrollment_not_found")
    res = await class_results(db, school_id, enr.classroom_id, period)
    mine = next(r for r in res["rows"] if r["enrollment_id"] == enr.id)
    student = await db.get(Student, enr.student_id)
    school = await db.get(School, school_id)
    remark = await db.scalar(select(PeriodRemark).where(PeriodRemark.enrollment_id == enr.id, PeriodRemark.period == (period or 3)))
    absences = (await db.scalars(select(Absence).where(Absence.school_id == school_id, Absence.enrollment_id == enr.id))).all()
    return {
        "school": {"name": school.name, "city": school.city}, "classroom": res["classroom"], "period": period,
        "student": {"id": student.id, "name": f"{student.last_name} {student.first_names}", "internal_number": student.internal_number, "matricule": student.matricule_mena},
        "lines": [{"subject": s["name"], "coef": s["coef"], "average": mine["subjects"][str(s["id"])], "class_average": res["subject_class_average"][str(s["id"])]} for s in res["subjects"] if mine["subjects"][str(s["id"])] is not None or s["coef"] > 0],
        "average": mine["average"], "rank": mine["rank"], "honour": mine["honour"], "passes": mine["passes"],
        "class_average": res["class_average"], "highest": res["highest"], "lowest": res["lowest"],
        "conduct": str(remark.conduct) if remark and remark.conduct is not None else None,
        "appreciation": remark.appreciation if remark else None, "sanction": remark.sanction if remark else None, "decision": remark.decision if remark else None,
        "absences": {
            "days_unjustified": sum(1 for a in absences if a.kind == "absence" and not a.justified), "days_justified": sum(1 for a in absences if a.kind == "absence" and a.justified),
            "late": sum(1 for a in absences if a.kind == "retard"),
        },
    }
