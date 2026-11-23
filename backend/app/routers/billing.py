"""The school's side of its subscription: what it owes, the notices from the Scolaris team. For the director and the secretary, even when the school is blocked."""

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.db import get_session
from app.deps import Me, current_me
from app.errors import NotFound
from app.models import School, SchoolNotice, SchoolNoticeSeen
from app.services import saas_billing

router = APIRouter(prefix="/v1", tags=["billing"])
BOTH = ("director", "secretary")


async def banner(db: AsyncSession, school: School, staff_id: int) -> dict | None:
    """The line shown at the top of the app to the director and the secretary: blocked, or a late subscription with the latest notice."""
    st = await saas_billing.standing(db, school.id, clock.now().date())
    last = await db.scalar(select(SchoolNotice).where(SchoolNotice.school_id == school.id, SchoolNotice.kind.in_(("reminder", "final_notice", "blocked"))).order_by(SchoolNotice.id.desc()).limit(1))
    unseen = int(await db.scalar(
        select(func.count()).select_from(SchoolNotice).outerjoin(SchoolNoticeSeen, (SchoolNoticeSeen.notice_id == SchoolNotice.id) & (SchoolNoticeSeen.staff_id == staff_id)).where(SchoolNotice.school_id == school.id, SchoolNoticeSeen.id.is_(None))) or 0)
    if school.status == "blocked":
        return {"level": "blocked", "title": "Accès suspendu", "text": last.text if last else "L'accès est suspendu pour impayé.", "unseen": unseen}
    if st is not None and st["late"] and last is not None:
        return {"level": "final" if last.kind == "final_notice" else "late", "title": last.title, "text": last.text, "block_on": last.block_on.isoformat() if last.block_on else None, "unseen": unseen}
    return {"level": "info", "title": "", "text": "", "unseen": unseen} if unseen else None


@router.get("/billing")
async def my_billing(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*BOTH)
    school = await db.get(School, m.school_id)
    notices = (await db.scalars(select(SchoolNotice).where(SchoolNotice.school_id == school.id).order_by(SchoolNotice.id.desc()).limit(30))).all()
    mine = set((await db.scalars(select(SchoolNoticeSeen.notice_id).where(SchoolNoticeSeen.staff_id == m.staff.id, SchoolNoticeSeen.notice_id.in_([n.id for n in notices] or [-1])))).all())
    return {
        "status": school.status, "standing": await saas_billing.standing(db, school.id, clock.now().date()),
        "notices": [{"id": n.id, "kind": n.kind, "title": n.title, "text": n.text, "block_on": n.block_on.isoformat() if n.block_on else None, "created_at": n.created_at.isoformat(), "seen": n.id in mine} for n in notices],
    }


@router.post("/billing/notices/{notice_id}/seen")
async def seen(notice_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """"I read it": the platform team sees how many of the school's director and secretary have read the notice."""
    m.require_role(*BOTH)
    if await db.scalar(select(SchoolNotice.id).where(SchoolNotice.id == notice_id, SchoolNotice.school_id == m.school_id)) is None:
        raise NotFound("notice_not_found")
    await db.execute(pg_insert(SchoolNoticeSeen).values(notice_id=notice_id, staff_id=m.staff.id).on_conflict_do_nothing(index_elements=["notice_id", "staff_id"]))
    await db.commit()
    return {"ok": True}
