"""The parent space: balance, receipts, report cards and absences of HER children, in whichever schools have her number."""

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.db import get_session
from app.deps import ParentMe, current_parent
from app.errors import BadRequest, NotFound
from app.models import AcademicYear, Absence, Classroom, Enrollment, Payment, School, Student
from app.services import academics, finance

router = APIRouter(prefix="/v1/parent", tags=["parent"])


async def _mine(db: AsyncSession, me: ParentMe, enrollment_id: int) -> Enrollment:
    """An enrolment of one of her children, or 404 (never 403: nothing tells her that another family's child exists)."""
    enr = await db.scalar(
        select(Enrollment).join(Student, Student.id == Enrollment.student_id).where(Enrollment.id == enrollment_id, Student.family_id.in_(me.family_ids or [-1]))
    )
    if enr is None:
        raise NotFound("not_found")
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
        _, acct = await finance.account(db, enr.school_id, enr.id, today)
        out.append({
            "enrollment_id": enr.id, "name": f"{st.first_names} {st.last_name}", "school": school.name, "classroom": room.name, "year": year.label,
            "balance": {"remaining": acct.remaining, "overdue": acct.overdue, "total_due": acct.total_due},
        })
    return out


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


@router.get("/children/{enrollment_id}/absences")
async def absences(enrollment_id: int, me: ParentMe = Depends(current_parent), db: AsyncSession = Depends(get_session)) -> list[dict]:
    enr = await _mine(db, me, enrollment_id)
    rows = await db.scalars(select(Absence).where(Absence.enrollment_id == enr.id, Absence.school_id == enr.school_id).order_by(Absence.day.desc()))
    return [{"day": a.day.isoformat(), "kind": a.kind, "slot": a.slot, "justified": a.justified, "reason": a.reason} for a in rows]
