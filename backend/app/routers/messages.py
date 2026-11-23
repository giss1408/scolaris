"""The school's message log: what was sent to families, what failed, and who must be phoned instead."""

from urllib.parse import quote

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from regisse_kit.phone import InvalidPhone, normalize_ci_phone
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app import clock
from app.config import get_settings
from app.db import get_session
from app.deps import Me, current_me
from app.errors import BadRequest, NotFound
from app.models import AuditLog, Contact, Family, OutboundMessage, School
from app.security import decrypt
from app.services import outbox

router = APIRouter(prefix="/v1", tags=["messages"])
READERS = ("director", "accountant", "secretary")


class SettingsIn(BaseModel):
    auto_whatsapp: bool | None = None
    whatsapp_phone: str | None = None  # the school's own WhatsApp number; "" removes it

    model_config = {"extra": "forbid"}


class OptinIn(BaseModel):
    whatsapp_optin: bool


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
    """The director enters the school's own WhatsApp number (messages to families are forwarded from it, replies arrive on it) and decides whether
    Scolaris may also send on its own."""
    m.require_role("director")
    school = await db.get(School, m.school_id)
    if "whatsapp_phone" in data.model_fields_set:
        raw = (data.whatsapp_phone or "").strip()
        if not raw:
            school.whatsapp_phone = None
        else:
            try:
                school.whatsapp_phone = normalize_ci_phone(raw, allow_test_numbers=get_settings().test_numbers)
            except InvalidPhone as e:
                raise BadRequest("phone_invalid", str(e)) from None
        db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="school.whatsapp_phone", entity="school", entity_id=school.id, detail={"set": school.whatsapp_phone is not None}))
    if data.auto_whatsapp is not None:
        school.auto_whatsapp = data.auto_whatsapp
        db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="school.auto_whatsapp", entity="school", entity_id=school.id, detail={"on": data.auto_whatsapp}))
    await db.commit()
    return {"auto_whatsapp": school.auto_whatsapp, "whatsapp_phone": school.whatsapp_phone}


def _wa_link(phone: str, text: str) -> str:
    return f"https://wa.me/{phone.lstrip('+')}?text={quote(text)}"


@router.get("/messages/to-send")
async def to_send(m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """What the app composed and a person must forward from the school's WhatsApp: one tap opens WhatsApp with the message ready."""
    m.require_role(*READERS)
    school = await db.get(School, m.school_id)
    rows = (await db.execute(
        select(OutboundMessage, Family.name).outerjoin(Family, Family.id == OutboundMessage.family_id)
        .where(OutboundMessage.school_id == m.school_id, OutboundMessage.status == "to_send").order_by(OutboundMessage.id)
    )).all()
    now = clock.now()
    return {
        "school_phone": school.whatsapp_phone, "can_send_now": outbox.in_window(now),
        "items": [{"id": x.id, "family": fam, "kind": x.kind, "text": x.preview, "created_at": x.created_at.isoformat(),
                   "wa_link": _wa_link(decrypt(x.to_phone_enc), x.preview) if x.to_phone_enc else None} for x, fam in rows],
    }


async def _manual(db: AsyncSession, m: Me, message_id: int) -> OutboundMessage:
    msg = await db.scalar(select(OutboundMessage).where(OutboundMessage.id == message_id, OutboundMessage.school_id == m.school_id))
    if msg is None:
        raise NotFound("message_not_found")
    return msg


@router.post("/messages/{message_id}/sent")
async def mark_sent(message_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """"I forwarded it." A second tap changes nothing."""
    m.require_role(*READERS)
    await _manual(db, m, message_id)
    res = await db.execute(update(OutboundMessage).where(OutboundMessage.id == message_id, OutboundMessage.school_id == m.school_id, OutboundMessage.status == "to_send")
                           .values(status="sent", sent_at=clock.now(), sent_by=m.staff.id))
    await db.commit()
    return {"ok": True, "changed": bool(res.rowcount)}


@router.post("/messages/{message_id}/skip")
async def skip_message(message_id: int, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    m.require_role(*READERS)
    await _manual(db, m, message_id)
    res = await db.execute(update(OutboundMessage).where(OutboundMessage.id == message_id, OutboundMessage.school_id == m.school_id, OutboundMessage.status == "to_send")
                           .values(status="skipped", detail="skipped_by_staff"))
    await db.commit()
    return {"ok": True, "changed": bool(res.rowcount)}


@router.put("/contacts/{contact_id}/optin")
async def set_optin(contact_id: int, data: OptinIn, m: Me = Depends(current_me), db: AsyncSession = Depends(get_session)) -> dict:
    """A parent says "stop writing to me" (or agrees again). Withdrawing takes effect at once: what was waiting to be sent is cancelled."""
    m.require_role(*READERS)
    c = await db.scalar(select(Contact).where(Contact.id == contact_id, Contact.school_id == m.school_id))
    if c is None:
        raise NotFound("contact_not_found")
    c.whatsapp_optin_at = clock.now() if data.whatsapp_optin else None
    cancelled = 0
    if not data.whatsapp_optin:
        res = await db.execute(update(OutboundMessage).where(OutboundMessage.school_id == m.school_id, OutboundMessage.contact_id == c.id, OutboundMessage.status.in_(("to_send", "queued")))
                               .values(status="skipped", detail="optin_withdrawn"))
        cancelled = res.rowcount or 0
    db.add(AuditLog(school_id=m.school_id, actor_id=m.staff.id, action="contact.whatsapp_optin", entity="contact", entity_id=c.id, detail={"optin": data.whatsapp_optin, "cancelled": cancelled}))
    await db.commit()
    return {"whatsapp_optin": data.whatsapp_optin, "cancelled_messages": cancelled}
