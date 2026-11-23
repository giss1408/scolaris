"""Fees, payments, receipts and arrears for one school. Every function takes `school_id` and filters on it."""

from collections import defaultdict
from datetime import date, datetime

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.errors import BadRequest, Conflict, NotFound
from app.levels import METHODS_NEEDING_REFERENCE
from app.models import (
    AcademicYear,
    AuditLog,
    Classroom,
    Contact,
    Discount,
    Enrollment,
    FeeInstallment,
    Payment,
    ReceiptCounter,
    Student,
)
from app.services.billing import Account, Due, applicable, build_account


async def get_enrollment(db: AsyncSession, school_id: int, enrollment_id: int) -> Enrollment:
    enr = await db.scalar(select(Enrollment).where(Enrollment.id == enrollment_id, Enrollment.school_id == school_id))
    if enr is None:
        raise NotFound("enrollment_not_found")
    return enr


def _dues_for(enr: Enrollment, student: Student, level: str, fees: list[FeeInstallment]) -> list[Due]:
    out = []
    for f in fees:
        if f.level != level or f.year_id != enr.year_id or not applicable(f.applies_to, student.assigned):
            continue
        if f.optional and f.kind not in (enr.options or []):
            continue
        out.append(Due(f.id, f.kind, f.label, f.amount, f.due_date))
    return out


async def _credits(db: AsyncSession, school_id: int, enrollment_ids: list[int] | None = None) -> dict[int, int]:
    """payments - credit notes + discounts, per enrolment."""
    totals: dict[int, int] = defaultdict(int)
    q1 = select(Payment.enrollment_id, func.sum(Payment.amount)).where(Payment.school_id == school_id).group_by(Payment.enrollment_id)
    q2 = select(Discount.enrollment_id, func.sum(Discount.amount)).where(Discount.school_id == school_id).group_by(Discount.enrollment_id)
    if enrollment_ids is not None:
        q1 = q1.where(Payment.enrollment_id.in_(enrollment_ids))
        q2 = q2.where(Discount.enrollment_id.in_(enrollment_ids))
    for q in (q1, q2):
        for eid, total in (await db.execute(q)).all():
            totals[eid] += int(total)
    return totals


async def account(db: AsyncSession, school_id: int, enrollment_id: int, today: date) -> tuple[Enrollment, Account]:
    enr = await get_enrollment(db, school_id, enrollment_id)
    student = await db.get(Student, enr.student_id)
    classroom = await db.get(Classroom, enr.classroom_id)
    fees = list((await db.scalars(select(FeeInstallment).where(FeeInstallment.school_id == school_id, FeeInstallment.year_id == enr.year_id, FeeInstallment.level == classroom.level))).all())
    credited = (await _credits(db, school_id, [enr.id])).get(enr.id, 0)
    return enr, build_account(_dues_for(enr, student, classroom.level, fees), credited, today)


async def next_number(db: AsyncSession, school_id: int, year: AcademicYear, prefix: str) -> str:
    """Gapless sequence: the counter row is created once, then locked until the payment commits (two cashiers never get the same number)."""
    await db.execute(pg_insert(ReceiptCounter).values(school_id=school_id, year_id=year.id, prefix=prefix, last=0).on_conflict_do_nothing())
    counter = await db.scalar(
        select(ReceiptCounter).where(ReceiptCounter.school_id == school_id, ReceiptCounter.year_id == year.id, ReceiptCounter.prefix == prefix).with_for_update()
    )
    counter.last += 1
    return f"{prefix}-{year.label[:4]}-{counter.last:06d}"


async def record_payment(
    db: AsyncSession, *, school_id: int, cashier_id: int, enrollment_id: int, amount: int, method: str, reference: str | None, idempotency_key: str | None, today: date
) -> tuple[Payment, Account]:
    if amount <= 0:
        raise BadRequest("amount_must_be_positive")
    if method in METHODS_NEEDING_REFERENCE and not (reference or "").strip():
        raise BadRequest("reference_required")
    if idempotency_key:
        prior = await db.scalar(select(Payment).where(Payment.school_id == school_id, Payment.idempotency_key == idempotency_key))
        if prior is not None:  # the app retried after a timeout: answer with the first result, record nothing new
            if prior.enrollment_id != enrollment_id or prior.amount != amount:
                raise Conflict("idempotency_key_reused")
            return prior, (await account(db, school_id, enrollment_id, today))[1]
    enr = await get_enrollment(db, school_id, enrollment_id)
    if enr.status != "active":
        raise BadRequest("enrollment_not_active")
    year = await db.get(AcademicYear, enr.year_id)
    pay = Payment(
        school_id=school_id, enrollment_id=enr.id, kind="payment", amount=amount, method=method, reference=(reference or "").strip() or None,
        receipt_number=await next_number(db, school_id, year, "REC"), cashier_id=cashier_id, idempotency_key=idempotency_key,
    )
    db.add(pay)
    db.add(AuditLog(school_id=school_id, actor_id=cashier_id, action="payment.recorded", entity="payment", detail={"enrollment_id": enr.id, "amount": amount, "method": method}))
    try:
        await db.commit()
    except IntegrityError:  # same idempotency key racing
        await db.rollback()
        raise Conflict("duplicate_payment") from None
    return pay, (await account(db, school_id, enr.id, today))[1]


async def void_payment(db: AsyncSession, *, school_id: int, actor_id: int, payment_id: int, reason: str, today: date) -> Payment:
    """A cancellation is a NEW row (credit note, negative, its own number) pointing at the payment. Nothing is deleted or edited."""
    original = await db.scalar(select(Payment).where(Payment.id == payment_id, Payment.school_id == school_id).with_for_update())
    if original is None:
        raise NotFound("payment_not_found")
    if original.kind != "payment":
        raise BadRequest("not_a_payment")
    if await db.scalar(select(Payment.id).where(Payment.reverses_id == original.id)):
        raise Conflict("already_cancelled")
    if not reason.strip():
        raise BadRequest("reason_required")
    enr = await db.get(Enrollment, original.enrollment_id)
    year = await db.get(AcademicYear, enr.year_id)
    note = Payment(
        school_id=school_id, enrollment_id=enr.id, kind="credit_note", amount=-original.amount, method=original.method, reference=original.reference,
        receipt_number=await next_number(db, school_id, year, "AV"), reverses_id=original.id, reason=reason.strip(), cashier_id=actor_id,
    )
    db.add(note)
    db.add(AuditLog(school_id=school_id, actor_id=actor_id, action="payment.cancelled", entity="payment", entity_id=original.id, detail={"amount": original.amount, "reason": reason.strip()}))
    await db.commit()
    return note


async def grant_discount(db: AsyncSession, *, school_id: int, actor_id: int, enrollment_id: int, kind: str, amount: int, reason: str, today: date) -> Discount:
    enr, acct = await account(db, school_id, enrollment_id, today)
    if amount <= 0:
        raise BadRequest("amount_must_be_positive")
    if not reason.strip():
        raise BadRequest("reason_required")
    already = int((await db.scalar(select(func.coalesce(func.sum(Discount.amount), 0)).where(Discount.enrollment_id == enr.id))) or 0)
    if already + amount > acct.total_due:  # a reduction can never exceed what is due
        raise BadRequest("discount_exceeds_total")
    d = Discount(school_id=school_id, enrollment_id=enr.id, kind=kind, amount=amount, reason=reason.strip(), granted_by=actor_id)
    db.add(d)
    db.add(AuditLog(school_id=school_id, actor_id=actor_id, action="discount.granted", entity="enrollment", entity_id=enr.id, detail={"kind": kind, "amount": amount, "reason": reason.strip()}))
    await db.commit()
    return d


async def arrears(db: AsyncSession, school_id: int, year_id: int, today: date, classroom_id: int | None = None) -> list[dict]:
    """Late lines grouped by family: one family, one row (the future reminder sends ONE message per family)."""
    q = select(Enrollment, Student, Classroom).join(Student, Student.id == Enrollment.student_id).join(Classroom, Classroom.id == Enrollment.classroom_id).where(
        Enrollment.school_id == school_id, Enrollment.year_id == year_id, Enrollment.status == "active"
    )
    if classroom_id:
        q = q.where(Enrollment.classroom_id == classroom_id)
    rows = (await db.execute(q)).all()
    if not rows:
        return []
    fees = list((await db.scalars(select(FeeInstallment).where(FeeInstallment.school_id == school_id, FeeInstallment.year_id == year_id))).all())
    credits = await _credits(db, school_id, [r[0].id for r in rows])
    families: dict[int, dict] = {}
    for enr, student, room in rows:
        acct = build_account(_dues_for(enr, student, room.level, fees), credits.get(enr.id, 0), today)
        if acct.overdue <= 0:
            continue
        fam = families.setdefault(student.family_id, {"family_id": student.family_id, "overdue_total": 0, "oldest_late_days": 0, "children": []})
        late = [ln for ln in acct.lines if ln.late_days > 0]
        fam["overdue_total"] += acct.overdue
        fam["oldest_late_days"] = max(fam["oldest_late_days"], max(ln.late_days for ln in late))
        fam["children"].append(
            {"enrollment_id": enr.id, "student_id": student.id, "name": f"{student.last_name} {student.first_names}", "classroom": room.name, "overdue": acct.overdue,
             "remaining": acct.remaining, "late_lines": [{"label": ln.label, "kind": ln.kind, "remaining": ln.remaining, "due_date": ln.due_date.isoformat(), "late_days": ln.late_days} for ln in late]}
        )
    if not families:
        return []
    from app.security import decrypt

    contacts = (await db.scalars(select(Contact).where(Contact.school_id == school_id, Contact.family_id.in_(list(families))))).all()
    by_family: dict[int, list[Contact]] = defaultdict(list)
    for c in contacts:
        by_family[c.family_id].append(c)
    from app.models import Family

    names = dict((await db.execute(select(Family.id, Family.name).where(Family.id.in_(list(families))))).all())
    out = []
    for fid, fam in families.items():
        people = sorted(by_family.get(fid, []), key=lambda c: not c.financial_responsible)
        main = people[0] if people else None
        fam["family_name"] = names.get(fid, "")
        fam["contact"] = {"name": main.name, "phone": decrypt(main.phone_enc), "channel": main.preferred_channel} if main else None
        out.append(fam)
    return sorted(out, key=lambda f: (-f["overdue_total"], f["family_name"]))


async def cash_summary(db: AsyncSession, school_id: int, year_id: int, today: date) -> dict:
    """Dashboard numbers: collected today / this month / this year (credit notes subtract), expected total, overdue."""
    start_today = datetime.combine(today, datetime.min.time()).astimezone()
    start_month = datetime.combine(today.replace(day=1), datetime.min.time()).astimezone()

    async def collected(since: datetime | None) -> int:
        q = select(func.coalesce(func.sum(Payment.amount), 0)).join(Enrollment, Enrollment.id == Payment.enrollment_id).where(Payment.school_id == school_id, Enrollment.year_id == year_id)
        if since:
            q = q.where(Payment.paid_at >= since)
        return int(await db.scalar(q) or 0)

    rows = (await db.execute(select(Enrollment, Student, Classroom).join(Student, Student.id == Enrollment.student_id).join(Classroom, Classroom.id == Enrollment.classroom_id).where(Enrollment.school_id == school_id, Enrollment.year_id == year_id, Enrollment.status == "active"))).all()
    fees = list((await db.scalars(select(FeeInstallment).where(FeeInstallment.school_id == school_id, FeeInstallment.year_id == year_id))).all())
    credits = await _credits(db, school_id, [r[0].id for r in rows]) if rows else {}
    expected = overdue = remaining = 0
    for enr, student, room in rows:
        a = build_account(_dues_for(enr, student, room.level, fees), credits.get(enr.id, 0), today)
        expected += a.total_due
        overdue += a.overdue
        remaining += a.remaining
    return {
        "collected_today": await collected(start_today), "collected_month": await collected(start_month), "collected_year": await collected(None),
        "expected_total": expected, "remaining_total": remaining, "overdue_total": overdue, "students": len(rows),
        "recovery_rate_pct": round(100 * (expected - remaining) / expected) if expected else 0,
    }
