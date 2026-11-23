"""Set-up of the school: years, classrooms, fee schedule, staff."""


import hashlib

from fastapi import APIRouter, Depends, Request, Response
from regisse_kit.phone import InvalidPhone, normalize_ci_phone
from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_session
from app.deps import Me, current_me
from app.errors import BadRequest, Conflict, NotFound
from app.levels import FEE_KINDS, LEVELS, PAYMENT_METHODS
from app.models import AcademicYear, AuditLog, Classroom, FeeInstallment, School, StaffMember, TimetableSlot
from app.schemas import ClassroomIn, FeeScheduleIn, StaffIn, YearIn
from app.services import academics, auth_client, images

router = APIRouter(prefix="/v1", tags=["school"])


@router.put("/school/logo")
async def put_logo(request: Request, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """The director sets the school's logo: the raw image as the request body (PNG or JPEG, at most 512 KB). It shows in the app and on the documents."""
    m.require_role("director")
    data = await request.body()
    if not data:
        raise BadRequest("empty_image", "Aucune image reçue.")
    if len(data) > images.MAX_BYTES:
        raise BadRequest("image_too_large", "L'image dépasse 512 Ko : choisissez un fichier plus léger.")
    found = images.sniff(data)  # by content: a renamed file or a wrong declared type does not pass
    if found is None:
        raise BadRequest("image_format", "Format non accepté : utilisez une image PNG ou JPEG.")
    ctype, w, h = found
    if not (images.MIN_SIDE <= w <= images.MAX_SIDE and images.MIN_SIDE <= h <= images.MAX_SIDE):
        raise BadRequest("image_size", f"L'image doit mesurer entre {images.MIN_SIDE} et {images.MAX_SIDE} pixels de côté.")
    school = await db.get(School, m.school_id)
    school.logo, school.logo_type = data, ctype
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="school.logo.set", entity="school", entity_id=school.id, detail={"bytes": len(data)}))
    await db.commit()
    return {"has_logo": True, "logo_version": logo_version(school)}


@router.delete("/school/logo")
async def delete_logo(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director")
    school = await db.get(School, m.school_id)
    school.logo = school.logo_type = None
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="school.logo.removed", entity="school", entity_id=school.id))
    await db.commit()
    return {"has_logo": False}


@router.get("/school/logo")
async def get_logo(request: Request, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> Response:
    return logo_response(request, await db.get(School, m.school_id))


@router.get("/me")
async def me(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    school = await db.get(School, m.school_id)
    year = await db.scalar(select(AcademicYear).where(AcademicYear.school_id == m.school_id, AcademicYear.is_current))
    return {
        "staff": {"id": m.staff.id, "name": m.staff.display_name, "role": m.role},
        "billing_banner": await _banner(db, school, m.staff.id) if m.role in ("director", "secretary") else None,
        "school": {"id": school.id, "name": school.name, "kind": school.kind, "city": school.city, "has_logo": school.logo is not None, "logo_version": logo_version(school),
                   "auto_whatsapp": school.auto_whatsapp, "phone": school.phone, "whatsapp_phone": school.whatsapp_phone,
                   "messages_to_send": await _to_send_count(db, school.id) if m.role in ("director", "secretary", "accountant") else 0},
        "current_year": {"id": year.id, "label": year.label} if year else None,
        "catalog": {"levels": LEVELS, "fee_kinds": FEE_KINDS, "methods": PAYMENT_METHODS},
    }


async def _to_send_count(db: AsyncSession, school_id: int) -> int:
    from sqlalchemy import func

    from app.models import OutboundMessage

    return int(await db.scalar(select(func.count()).select_from(OutboundMessage).where(OutboundMessage.school_id == school_id, OutboundMessage.status == "to_send")) or 0)


async def _banner(db: AsyncSession, school: School, staff_id: int):
    from app.routers.billing import banner

    return await banner(db, school, staff_id)


def logo_version(school: School) -> str | None:
    return hashlib.sha256(school.logo).hexdigest()[:16] if school.logo else None


def logo_response(request: Request, school: School) -> Response:
    """The image with a cache validator: the app asks again with If-None-Match and gets a 304 until the logo changes."""
    if not school.logo:
        raise NotFound("no_logo")
    etag = f'"{logo_version(school)}"'
    headers = {"ETag": etag, "Cache-Control": "private, max-age=3600", "X-Content-Type-Options": "nosniff"}
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    return Response(content=school.logo, media_type=school.logo_type, headers=headers)


def _year(y: AcademicYear) -> dict:
    return {"id": y.id, "label": y.label, "starts_on": y.starts_on.isoformat(), "ends_on": y.ends_on.isoformat(), "is_current": y.is_current}


@router.get("/years")
async def years(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    rows = await db.scalars(select(AcademicYear).where(AcademicYear.school_id == m.school_id).order_by(AcademicYear.starts_on.desc()))
    return [_year(y) for y in rows]


@router.post("/years", status_code=201)
async def create_year(data: YearIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director")
    if data.ends_on <= data.starts_on:
        raise BadRequest("dates_invalid")
    if data.is_current:
        await db.execute(update(AcademicYear).where(AcademicYear.school_id == m.school_id).values(is_current=False))
    y = AcademicYear(school_id=m.school_id, **data.model_dump())
    db.add(y)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise Conflict("year_exists") from None
    return _year(y)


def _room(c: Classroom) -> dict:
    return {"id": c.id, "year_id": c.year_id, "level": c.level, "series": c.series, "name": c.name, "capacity": c.capacity}


@router.get("/classrooms")
async def classrooms(year_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    rows = await db.scalars(select(Classroom).where(Classroom.school_id == m.school_id, Classroom.year_id == year_id).order_by(Classroom.name))
    visible = await academics.viewable_classroom_ids(db, m.school_id, m.role, m.staff.id, year_id)  # a teacher sees her classes only
    return [{**_room(c), "is_head": c.head_teacher_id == m.staff.id} for c in rows if visible is None or c.id in visible]


@router.post("/classrooms", status_code=201)
async def create_classroom(data: ClassroomIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director", "secretary")
    if await db.scalar(select(AcademicYear.id).where(AcademicYear.id == data.year_id, AcademicYear.school_id == m.school_id)) is None:
        raise NotFound("year_not_found")
    c = Classroom(school_id=m.school_id, **data.model_dump())
    db.add(c)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise Conflict("classroom_exists") from None
    return _room(c)


def _fee(f: FeeInstallment) -> dict:
    return {"id": f.id, "level": f.level, "kind": f.kind, "label": f.label, "amount": f.amount, "due_date": f.due_date.isoformat(), "optional": f.optional, "applies_to": f.applies_to}


@router.get("/fees")
async def fees(year_id: int, level: str | None = None, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    q = select(FeeInstallment).where(FeeInstallment.school_id == m.school_id, FeeInstallment.year_id == year_id).order_by(FeeInstallment.level, FeeInstallment.due_date, FeeInstallment.id)
    if level:
        q = q.where(FeeInstallment.level == level)
    return [_fee(f) for f in await db.scalars(q)]


@router.put("/fees")
async def replace_fees(data: FeeScheduleIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    """Replace one level's schedule for one year. Refused once money has been collected on that level: changing prices under payments
    already received would silently change what families owe (create a new line or a discount instead)."""
    from app.models import Enrollment, Payment

    m.require_role("director")
    if await db.scalar(select(AcademicYear.id).where(AcademicYear.id == data.year_id, AcademicYear.school_id == m.school_id)) is None:
        raise NotFound("year_not_found")
    touched = await db.scalar(
        select(Payment.id).join(Enrollment, Enrollment.id == Payment.enrollment_id).join(Classroom, Classroom.id == Enrollment.classroom_id)
        .where(Payment.school_id == m.school_id, Enrollment.year_id == data.year_id, Classroom.level == data.level).limit(1)
    )
    if touched is not None:
        raise Conflict("fees_locked_by_payments")
    await db.execute(delete(FeeInstallment).where(FeeInstallment.school_id == m.school_id, FeeInstallment.year_id == data.year_id, FeeInstallment.level == data.level))
    rows = [FeeInstallment(school_id=m.school_id, year_id=data.year_id, level=data.level, **ln.model_dump()) for ln in data.lines]
    db.add_all(rows)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="fees.replaced", entity="fee_schedule", detail={"year_id": data.year_id, "level": data.level, "lines": len(rows)}))
    await db.commit()
    return [_fee(f) for f in rows]


@router.get("/staff")
async def staff(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    m.require_role("director")
    rows = await db.scalars(select(StaffMember).where(StaffMember.school_id == m.school_id).order_by(StaffMember.id))
    return [{"id": s.id, "name": s.display_name, "role": s.role, "active": s.active} for s in rows]


@router.get("/teachers")
async def teachers(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> list[dict]:
    """The active teachers of the school (names only): the direction and the secretary pick a replacement among them."""
    m.require_role("director", "secretary")
    rows = await db.scalars(select(StaffMember).where(StaffMember.school_id == m.school_id, StaffMember.role == "teacher", StaffMember.active).order_by(StaffMember.display_name))
    return [{"id": t.id, "name": t.display_name} for t in rows]


@router.post("/staff", status_code=201)
async def add_staff(data: StaffIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """The director enrols her team: pending account at auth, the platform team sends the WhatsApp code, the person picks her own password."""
    m.require_role("director")
    try:
        phone = normalize_ci_phone(data.phone, allow_test_numbers=get_settings().test_numbers)
    except InvalidPhone as e:
        raise BadRequest("phone_invalid", str(e)) from None
    uid = await auth_client.enrol_staff(phone=phone, display_name=data.display_name, role=data.role)
    s = StaffMember(school_id=m.school_id, auth_user_id=uid, display_name=data.display_name.strip(), role=data.role)
    db.add(s)
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="staff.enrolled", entity="staff", detail={"role": data.role}))
    await db.commit()
    return {"id": s.id, "name": s.display_name, "role": s.role, "activation": "whatsapp_code_from_team"}


@router.delete("/staff/{staff_id}")
async def remove_staff(staff_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role("director")
    s = await db.scalar(select(StaffMember).where(StaffMember.id == staff_id, StaffMember.school_id == m.school_id))
    if s is None:
        raise NotFound("staff_not_found")
    if s.role == "director":
        raise BadRequest("cannot_remove_director")
    s.active = False
    await db.execute(update(TimetableSlot).where(TimetableSlot.school_id == m.school_id, TimetableSlot.teacher_id == s.id).values(teacher_id=None))  # her periods stay, unassigned
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="staff.removed", entity="staff", entity_id=s.id))
    await db.commit()
    await auth_client.remove_staff(s.auth_user_id)
    return {"ok": True}
