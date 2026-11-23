"""The parent space: balance, receipts, report cards and absences of HER children, in whichever schools have her number."""

from datetime import date, timedelta

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.db import get_session
from app.deps import ParentMe, current_parent
from app.errors import BadRequest, Forbidden, NotFound
from app.models import AcademicYear, Absence, Classroom, Enrollment, Payment, School, Student
from app.schemas import AbsenceReportIn
from app.services import academics, finance

router = APIRouter(prefix="/v1/parent", tags=["parent"])


def _logo_version(school: School) -> str | None:
    from app.routers.school import logo_version

    return logo_version(school)


async def _mine(db: AsyncSession, me: ParentMe, enrollment_id: int) -> Enrollment:
    """An enrolment of one of her children, or 404 (never 403: nothing tells her that another family's child exists)."""
    enr = await db.scalar(
        select(Enrollment).join(Student, Student.id == Enrollment.student_id).where(Enrollment.id == enrollment_id, Student.family_id.in_(me.family_ids or [-1]))
    )
    if enr is None:
        raise NotFound("not_found")
    if (await db.get(School, enr.school_id)).status == "blocked":
        raise Forbidden("school_blocked", "Le service est suspendu pour cet établissement. Contactez l'école.")
    return enr


@router.get("/children")
async def children(me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> list[dict]:
    if not me.family_ids:
        return []
    rows = (await db.execute(
        select(Enrollment, Student, Classroom, AcademicYear, School)
        .join(Student, Student.id == Enrollment.student_id).join(Classroom, Classroom.id == Enrollment.classroom_id)
        .join(AcademicYear, AcademicYear.id == Enrollment.year_id).join(School, School.id == Enrollment.school_id)
        .where(Student.family_id.in_(me.family_ids), AcademicYear.is_current, Enrollment.status == "active").order_by(School.name, Student.first_names)
    )).all()
    today = clock.now().date()
    out = []
    for enr, st, room, year, school in rows:
        if school.status == "blocked":  # the school's service is suspended: she is told so, nothing else is shown
            out.append({"enrollment_id": enr.id, "name": f"{st.first_names} {st.last_name}", "school": school.name, "school_id": school.id, "has_logo": school.logo is not None, "logo_version": _logo_version(school),
                        "classroom": room.name, "year": year.label, "blocked": True, "balance": {"remaining": 0, "overdue": 0, "total_due": 0}})
            continue
        _, acct = await finance.account(db, enr.school_id, enr.id, today)
        out.append({
            "enrollment_id": enr.id, "name": f"{st.first_names} {st.last_name}", "school": school.name, "school_id": school.id, "has_logo": school.logo is not None, "logo_version": _logo_version(school), "classroom": room.name, "year": year.label,
            "balance": {"remaining": acct.remaining, "overdue": acct.overdue, "total_due": acct.total_due},
        })
    return out


@router.get("/schools/{school_id}/logo")
async def school_logo(school_id: int, request: Request, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)):
    """The logo of a school where she has a child (and only those)."""
    from app.routers.school import logo_response

    ok = await db.scalar(select(Enrollment.id).join(Student, Student.id == Enrollment.student_id).where(Enrollment.school_id == school_id, Student.family_id.in_(me.family_ids or [-1])).limit(1))
    if ok is None:
        raise NotFound("not_found")
    return logo_response(request, await db.get(School, school_id))


@router.get("/children/{enrollment_id}/payments")
async def payments(enrollment_id: int, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> list[dict]:
    enr = await _mine(db, me, enrollment_id)
    rows = await db.scalars(select(Payment).where(Payment.enrollment_id == enr.id, Payment.school_id == enr.school_id).order_by(Payment.paid_at.desc(), Payment.id.desc()))
    return [{"id": p.id, "kind": p.kind, "amount": p.amount, "method": p.method, "receipt_number": p.receipt_number, "paid_at": p.paid_at.isoformat()} for p in rows]


@router.get("/children/{enrollment_id}/report-card")
async def report_card(enrollment_id: int, period: int = 1, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> dict:
    enr = await _mine(db, me, enrollment_id)
    if period not in (0, 1, 2, 3):
        raise BadRequest("period_invalid")
    card = await academics.report_card(db, enr.school_id, enr.id, period)
    card.pop("class_average", None)  # the class's figures stay with the school
    card.pop("highest", None)
    card.pop("lowest", None)
    for line in card["lines"]:
        line.pop("class_average", None)
    return card


@router.get("/children/{enrollment_id}/timetable")
async def timetable(enrollment_id: int, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> dict:
    enr = await _mine(db, me, enrollment_id)
    from app.models import TimetableSlot
    from app.routers.timetable import slots_json

    from app.routers.timetable import cancellations_json

    return {"slots": await slots_json(db, enr.school_id, TimetableSlot.classroom_id == enr.classroom_id),
            "cancellations": await cancellations_json(db, enr.school_id, TimetableSlot.classroom_id == enr.classroom_id, viewer_role=None)}


@router.get("/children/{enrollment_id}/absences")
async def absences(enrollment_id: int, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> list[dict]:
    enr = await _mine(db, me, enrollment_id)
    from app.models import Subject, TimetableSlot

    rows = (await db.execute(
        select(Absence, Subject.name, TimetableSlot.start_time, TimetableSlot.end_time).outerjoin(TimetableSlot, TimetableSlot.id == Absence.slot_id).outerjoin(Subject, Subject.id == TimetableSlot.subject_id)
        .where(Absence.enrollment_id == enr.id, Absence.school_id == enr.school_id).order_by(Absence.day.desc(), TimetableSlot.start_time)
    )).all()
    return [{"day": a.day.isoformat(), "kind": a.kind, "slot": a.slot, "justified": a.justified, "reason": a.reason,
             "course": ({"subject": sub, "start": st.strftime("%H:%M"), "end": en.strftime("%H:%M")} if sub else None)} for a, sub, st, en in rows]


@router.post("/children/{enrollment_id}/absence-reports", status_code=201)
async def report_absence(enrollment_id: int, data: AbsenceReportIn, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> dict:
    """A parent tells the school her child is absent for a day (today, a coming day up to two weeks ahead, or one of the last three days to explain it).
    Sending it again for the same day updates it. The school sees it in the roll call; it does not justify the absence by itself."""
    from sqlalchemy.dialects.postgresql import insert as pg_insert

    from app.models import AbsenceReport, Contact

    enr = await _mine(db, me, enrollment_id)
    today = clock.now().date()
    if data.day < today - timedelta(days=3) or data.day > today + timedelta(days=14):
        raise BadRequest("day_out_of_range", "Choisissez un jour entre les 3 derniers jours et les 14 prochains.")
    if data.day.isoweekday() == 7:
        raise BadRequest("no_school_on_sunday", "Il n'y a pas classe le dimanche.")
    note = (data.note or "").strip() or None
    if data.reason == "autre" and (note is None or len(note) < 3):
        raise BadRequest("note_required", "Précisez le motif.")
    st = await db.get(Student, enr.student_id)
    contact = await db.scalar(select(Contact.id).where(Contact.family_id == st.family_id, Contact.phone_hash == me.phone_hash))
    stmt = pg_insert(AbsenceReport).values(school_id=enr.school_id, enrollment_id=enr.id, day=data.day, reason=data.reason, note=note, contact_id=contact)
    await db.execute(stmt.on_conflict_do_update(index_elements=["enrollment_id", "day"], set_={"reason": data.reason, "note": note, "contact_id": contact}))
    await db.commit()
    return {"day": data.day.isoformat(), "reason": data.reason, "note": note}


@router.get("/children/{enrollment_id}/absence-reports")
async def my_reports(enrollment_id: int, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> list[dict]:
    from app.models import AbsenceReport

    enr = await _mine(db, me, enrollment_id)
    since = clock.now().date() - timedelta(days=3)
    rows = await db.scalars(select(AbsenceReport).where(AbsenceReport.enrollment_id == enr.id, AbsenceReport.day >= since).order_by(AbsenceReport.day))
    return [{"day": r.day.isoformat(), "reason": r.reason, "note": r.note} for r in rows]


@router.delete("/children/{enrollment_id}/absence-reports/{day}")
async def withdraw_report(enrollment_id: int, day: date, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> dict:
    """She changed her mind (the child will come after all). Only for today and later: a past day stays as it was told."""
    from app.models import AbsenceReport

    enr = await _mine(db, me, enrollment_id)
    if day < clock.now().date():
        raise BadRequest("date_in_the_past", "Cette date est passée.")
    r = await db.scalar(select(AbsenceReport).where(AbsenceReport.enrollment_id == enr.id, AbsenceReport.day == day))
    if r is None:
        raise NotFound("report_not_found")
    await db.delete(r)
    await db.commit()
    return {"ok": True}
