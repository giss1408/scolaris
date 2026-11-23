"""Collecting money: a student's account, payments, receipts, cancellations (credit notes), discounts, arrears, dashboard."""

from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.deps import Me, current_me
from app.errors import NotFound
from app.models import AcademicYear, Classroom, Discount, Payment, School, Student
from app.schemas import DiscountIn, PaymentIn, VoidIn
from app.services import finance
from app.services.billing import Account

router = APIRouter(prefix="/v1", tags=["money"])


def _today() -> date:
    return date.today()


def _account(acct: Account) -> dict:
    return {
        "total_due": acct.total_due, "credited": acct.credited, "remaining": acct.remaining, "overdue": acct.overdue, "credit_balance": acct.credit_balance,
        "lines": [{"id": ln.id, "kind": ln.kind, "label": ln.label, "amount": ln.amount, "due_date": ln.due_date.isoformat(), "covered": ln.covered, "remaining": ln.remaining, "late_days": ln.late_days} for ln in acct.lines],
    }


def _payment(p: Payment) -> dict:
    return {"id": p.id, "kind": p.kind, "amount": p.amount, "method": p.method, "reference": p.reference, "receipt_number": p.receipt_number, "reverses_id": p.reverses_id,
            "reason": p.reason, "paid_at": p.paid_at.isoformat()}


@router.get("/enrollments/{enrollment_id}/account")
async def enrollment_account(enrollment_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    enr, acct = await finance.account(db, m.school_id, enrollment_id, _today())
    student = await db.get(Student, enr.student_id)
    room = await db.get(Classroom, enr.classroom_id)
    pays = (await db.scalars(select(Payment).where(Payment.enrollment_id == enr.id, Payment.school_id == m.school_id).order_by(Payment.paid_at.desc(), Payment.id.desc()))).all()
    discounts = (await db.scalars(select(Discount).where(Discount.enrollment_id == enr.id, Discount.school_id == m.school_id).order_by(Discount.id))).all()
    cancelled = {p.reverses_id for p in pays if p.reverses_id}
    return {
        "enrollment_id": enr.id, "student": {"id": student.id, "name": f"{student.last_name} {student.first_names}", "assigned": student.assigned}, "classroom": room.name,
        "account": _account(acct),
        "payments": [{**_payment(p), "cancelled": p.id in cancelled} for p in pays],
        "discounts": [{"id": d.id, "kind": d.kind, "amount": d.amount, "reason": d.reason} for d in discounts],
    }


@router.post("/enrollments/{enrollment_id}/payments", status_code=201)
async def add_payment(enrollment_id: int, data: PaymentIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "accountant")
    pay, acct = await finance.record_payment(
        db, school_id=m.school_id, cashier_id=m.staff.id, enrollment_id=enrollment_id, amount=data.amount, method=data.method, reference=data.reference,
        idempotency_key=data.idempotency_key, today=_today(),
    )
    return {"payment": _payment(pay), "account": _account(acct)}


@router.post("/payments/{payment_id}/cancel", status_code=201)
async def cancel_payment(payment_id: int, data: VoidIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "accountant")
    await m.require_recent_password()
    note = await finance.void_payment(db, school_id=m.school_id, actor_id=m.staff.id, payment_id=payment_id, reason=data.reason, today=_today())
    _, acct = await finance.account(db, m.school_id, note.enrollment_id, _today())
    return {"credit_note": _payment(note), "account": _account(acct)}


@router.post("/enrollments/{enrollment_id}/discounts", status_code=201)
async def add_discount(enrollment_id: int, data: DiscountIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director")
    await m.require_recent_password()
    d = await finance.grant_discount(db, school_id=m.school_id, actor_id=m.staff.id, enrollment_id=enrollment_id, kind=data.kind, amount=data.amount, reason=data.reason, today=_today())
    _, acct = await finance.account(db, m.school_id, enrollment_id, _today())
    return {"discount": {"id": d.id, "kind": d.kind, "amount": d.amount, "reason": d.reason}, "account": _account(acct)}


@router.get("/payments/{payment_id}/receipt")
async def receipt(payment_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """Everything the printed receipt (A4 or 80 mm ticket) needs. The number is fixed once issued; the data never changes."""
    p = await db.scalar(select(Payment).where(Payment.id == payment_id, Payment.school_id == m.school_id))
    if p is None:
        raise NotFound("payment_not_found")
    enr, acct = await finance.account(db, m.school_id, p.enrollment_id, _today())
    student = await db.get(Student, enr.student_id)
    room = await db.get(Classroom, enr.classroom_id)
    year = await db.get(AcademicYear, enr.year_id)
    school = await db.get(School, m.school_id)
    from app.models import StaffMember

    cashier = await db.get(StaffMember, p.cashier_id)
    return {
        "school": {"name": school.name, "city": school.city}, "year": year.label, "kind": p.kind, "number": p.receipt_number, "date": p.paid_at.isoformat(),
        "student": {"name": f"{student.last_name} {student.first_names}", "internal_number": student.internal_number, "classroom": room.name},
        "amount": p.amount, "method": p.method, "reference": p.reference, "reason": p.reason, "reverses_id": p.reverses_id,
        "remaining_after": acct.remaining, "cashier": cashier.display_name,
    }


@router.get("/arrears")
async def arrears(year_id: int, classroom_id: int | None = None, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    m.require_role("director", "accountant")
    return await finance.arrears(db, m.school_id, year_id, _today(), classroom_id)


@router.get("/dashboard")
async def dashboard(year_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "accountant")
    return await finance.cash_summary(db, m.school_id, year_id, _today())
