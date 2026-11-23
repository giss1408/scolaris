"""Students, families and contacts."""

from datetime import datetime

from fastapi import APIRouter, Depends
from regisse_kit.phone import InvalidPhone, mask_phone, normalize_ci_phone
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_session
from app.deps import Me, current_me
from app.errors import BadRequest, Conflict, NotFound
from app.models import AcademicYear, AuditLog, Classroom, Contact, Enrollment, Family, FeeInstallment, Student
from app.schemas import ContactIn, EnrollIn, StudentIn
from app.security import decrypt, encrypt, phone_hash
from app.services import finance

router = APIRouter(prefix="/v1", tags=["students"])


def _phone(raw: str) -> str:
    try:
        return normalize_ci_phone(raw, allow_test_numbers=get_settings().test_numbers)
    except InvalidPhone as e:
        raise BadRequest("phone_invalid", str(e)) from None


def _contact(c: Contact) -> dict:
    phone = decrypt(c.phone_enc)
    return {"id": c.id, "name": c.name, "relation": c.relation, "phone": phone, "phone_masked": mask_phone(phone), "preferred_channel": c.preferred_channel,
            "whatsapp_optin": c.whatsapp_optin_at is not None, "financial_responsible": c.financial_responsible}


def _student(s: Student) -> dict:
    return {"id": s.id, "internal_number": s.internal_number, "matricule_mena": s.matricule_mena, "last_name": s.last_name, "first_names": s.first_names, "sex": s.sex,
            "birth_date": s.birth_date.isoformat() if s.birth_date else None, "birth_place": s.birth_place, "assigned": s.assigned, "family_id": s.family_id}


async def _add_contact(db: AsyncSession, school_id: int, family_id: int, data: ContactIn) -> None:
    phone = _phone(data.phone)
    h = phone_hash(phone)
    if await db.scalar(select(Contact.id).where(Contact.family_id == family_id, Contact.phone_hash == h)):
        return  # same number twice in one family: keep one
    db.add(Contact(school_id=school_id, family_id=family_id, name=data.name.strip(), relation=data.relation, phone_enc=encrypt(phone), phone_hash=h,
                   preferred_channel=data.preferred_channel, whatsapp_optin_at=datetime.now().astimezone() if data.whatsapp_optin else None,
                   financial_responsible=data.financial_responsible))


async def _enroll(db: AsyncSession, m: Me, student: Student, e: EnrollIn) -> Enrollment:
    room = await db.scalar(select(Classroom).where(Classroom.id == e.classroom_id, Classroom.school_id == m.school_id))
    if room is None:
        raise NotFound("classroom_not_found")
    offered = set((await db.scalars(select(FeeInstallment.kind).where(
        FeeInstallment.school_id == m.school_id, FeeInstallment.year_id == room.year_id, FeeInstallment.level == room.level, FeeInstallment.optional))).all())
    bad = [k for k in e.options if k not in offered]
    if bad:
        raise BadRequest("option_not_offered", ", ".join(bad))
    enr = Enrollment(school_id=m.school_id, student_id=student.id, classroom_id=room.id, year_id=room.year_id, options=sorted(set(e.options)))
    db.add(enr)
    return enr


@router.post("/students", status_code=201)
async def create_student(data: StudentIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "secretary")
    room = await db.scalar(select(Classroom).where(Classroom.id == data.enrollment.classroom_id, Classroom.school_id == m.school_id))
    if room is None:
        raise NotFound("classroom_not_found")
    year = await db.get(AcademicYear, room.year_id)
    if data.family_id is not None:
        family = await db.scalar(select(Family).where(Family.id == data.family_id, Family.school_id == m.school_id))
        if family is None:
            raise NotFound("family_not_found")
    else:
        family = Family(school_id=m.school_id, name=data.last_name.strip().upper())
        db.add(family)
        await db.flush()
    for c in data.contacts:
        await _add_contact(db, m.school_id, family.id, c)
    student = Student(
        school_id=m.school_id, family_id=family.id, internal_number=await finance.next_number(db, m.school_id, year, "ELV"), matricule_mena=data.matricule_mena,
        last_name=data.last_name.strip().upper(), first_names=data.first_names.strip(), sex=data.sex, birth_date=data.birth_date, birth_place=data.birth_place, assigned=data.assigned,
    )
    db.add(student)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise Conflict("matricule_already_used") from None
    enr = await _enroll(db, m, student, data.enrollment)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="student.created", entity="student", entity_id=student.id))
    await db.commit()
    await db.refresh(enr)
    return {**_student(student), "enrollment_id": enr.id}


@router.get("/students")
async def list_students(
    year_id: int, q: str | None = None, classroom_id: int | None = None, limit: int = 50, offset: int = 0,
    m: Me = Depends(current_me), db: AsyncSession = Depends(get_session),
) -> list[dict]:
    m.require_role("director", "accountant", "secretary")  # a teacher reaches her pupils through her classes, not the school register
    stmt = (
        select(Student, Enrollment, Classroom).join(Enrollment, Enrollment.student_id == Student.id).join(Classroom, Classroom.id == Enrollment.classroom_id)
        .where(Student.school_id == m.school_id, Enrollment.year_id == year_id, Enrollment.status == "active")
        .order_by(Student.last_name, Student.first_names).limit(min(max(limit, 1), 200)).offset(max(offset, 0))
    )
    if classroom_id:
        stmt = stmt.where(Enrollment.classroom_id == classroom_id)
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(Student.last_name.ilike(like), Student.first_names.ilike(like), Student.matricule_mena.ilike(like), Student.internal_number.ilike(like)))
    return [{**_student(s), "enrollment_id": e.id, "classroom": c.name, "level": c.level} for s, e, c in (await db.execute(stmt)).all()]


@router.get("/students/{student_id}")
async def student_detail(student_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "accountant", "secretary")
    s = await db.scalar(select(Student).where(Student.id == student_id, Student.school_id == m.school_id))
    if s is None:
        raise NotFound("student_not_found")
    contacts = (await db.scalars(select(Contact).where(Contact.family_id == s.family_id, Contact.school_id == m.school_id).order_by(Contact.id))).all()
    siblings = (await db.scalars(select(Student).where(Student.family_id == s.family_id, Student.school_id == m.school_id, Student.id != s.id))).all()
    rows = (await db.execute(select(Enrollment, Classroom).join(Classroom, Classroom.id == Enrollment.classroom_id).where(Enrollment.student_id == s.id, Enrollment.school_id == m.school_id).order_by(Enrollment.year_id.desc()))).all()
    return {
        **_student(s), "contacts": [_contact(c) for c in contacts], "siblings": [{"id": x.id, "name": f"{x.last_name} {x.first_names}"} for x in siblings],
        "enrollments": [{"id": e.id, "year_id": e.year_id, "classroom": c.name, "level": c.level, "status": e.status, "options": e.options} for e, c in rows],
    }


@router.post("/students/{student_id}/contacts", status_code=201)
async def add_contact(student_id: int, data: ContactIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "secretary")
    s = await db.scalar(select(Student).where(Student.id == student_id, Student.school_id == m.school_id))
    if s is None:
        raise NotFound("student_not_found")
    await _add_contact(db, m.school_id, s.family_id, data)
    await db.commit()
    return {"ok": True}
