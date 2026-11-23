"""The school's message log: what was sent to families, what failed, and who must be phoned instead."""

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.deps import Me, current_me
from app.models import AuditLog, Family, OutboundMessage, School
from app.services import outbox

router = APIRouter(prefix="/v1", tags=["messages"])
READERS = ("director", "accountant", "secretary")


class SettingsIn(BaseModel):
    auto_whatsapp: bool | None = None


@router.get("/messages")
async def messages(status: str | None = None, kind: str | None = None, limit: int = 100, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*READERS)
    q = select(OutboundMessage, Family.name).outerjoin(Family, Family.id == OutboundMessage.family_id).where(OutboundMessage.school_id == m.school_id).order_by(OutboundMessage.id.desc()).limit(min(max(limit, 1), 300))
    if status:
        q = q.where(OutboundMessage.status.in_(status.split(",")))
    if kind:
        q = q.where(OutboundMessage.kind == kind)
    rows = (await db.execute(q)).all()
    return {
        "summary": await outbox.summary(db, m.school_id),
        "items": [{"id": x.id, "family": fam, "kind": x.kind, "status": x.status, "detail": x.detail, "text": x.preview, "created_at": x.created_at.isoformat(),
                   "needs_call": x.status in ("failed", "skipped")} for x, fam in rows],
    }


@router.put("/school/settings")
async def settings(data: SettingsIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """The director decides whether Scolaris may send reminders and notices to families by WhatsApp on its own."""
    m.require_role("director")
    school = await db.get(School, m.school_id)
    if data.auto_whatsapp is not None:
        school.auto_whatsapp = data.auto_whatsapp
        db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="school.auto_whatsapp", entity="school", entity_id=school.id, detail={"on": data.auto_whatsapp}))
    await db.commit()
    return {"auto_whatsapp": school.auto_whatsapp}
