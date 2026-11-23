"""Messages to families: queue (idempotent), send within the allowed hours, follow the delivery, never contact someone who did not agree.

Rules (from the school-management skill): only with the parent's WhatsApp opt-in and her preferred channel; not between 20:00 and 07:00 nor on
Sunday; a failed message falls back to "à appeler" (status failed/skipped, listed for the staff); the same notice is never queued twice.
"""

import logging
from collections import defaultdict
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.integrations import whatsapp
from app.models import Contact, OutboundMessage, School
from app.security import decrypt
from app.services.reminders import SEND_FROM, SEND_UNTIL, pick_contact

log = logging.getLogger("scolaris.outbox")
MAX_ATTEMPTS = 4


def in_window(now: datetime) -> bool:
    return now.weekday() != 6 and SEND_FROM <= now.hour < SEND_UNTIL


def next_window(now: datetime) -> datetime:
    """The next moment a message may go out (07:00 of the next allowed day if now is outside the window)."""
    t = now
    if in_window(t):
        return t
    t = t.replace(minute=0, second=0, microsecond=0)
    if t.hour >= SEND_UNTIL or t.weekday() == 6:
        t = (t + timedelta(days=1)).replace(hour=SEND_FROM)
    elif t.hour < SEND_FROM:
        t = t.replace(hour=SEND_FROM)
    while t.weekday() == 6:
        t = (t + timedelta(days=1)).replace(hour=SEND_FROM)
    return t


async def enqueue(db: AsyncSession, *, school_id: int, family_id: int, kind: str, text: str, dedupe_key: str, now: datetime, contacts: list[Contact] | None = None) -> OutboundMessage | None:
    """Queue ONE message for a family (the responsible parent first). No opt-in: recorded as `skipped` so the staff know to phone. Returns None if already queued."""
    school = await db.get(School, school_id)
    automatic = school.auto_whatsapp
    if school.status != "active" or not (automatic or school.whatsapp_phone):
        return None  # no number entered by the director and automatic sending off (or the school is blocked): nothing is composed, nothing is sent
    if contacts is None:
        contacts = list((await db.scalars(select(Contact).where(Contact.school_id == school_id, Contact.family_id == family_id))).all())
    contact, channel = pick_contact(contacts)
    params = [whatsapp.clean(contact.name if contact else "Madame, Monsieur", 80), whatsapp.clean(school.name, 80), whatsapp.clean(text)]
    values = dict(school_id=school_id, family_id=family_id, contact_id=contact.id if contact else None, kind=kind, template=get_template(), params=params, preview=whatsapp.render(params), dedupe_key=dedupe_key)
    if contact is None or channel != "whatsapp":
        values.update(status="skipped", detail="no_whatsapp_optin" if contact else "no_contact")
    elif automatic:
        values.update(status="queued", to_phone_enc=contact.phone_enc, next_attempt_at=next_window(now))
    else:  # the school's secretary forwards it from the school's own WhatsApp number
        values.update(status="to_send", to_phone_enc=contact.phone_enc)
    res = await db.execute(pg_insert(OutboundMessage).values(**values).on_conflict_do_nothing(index_elements=["school_id", "dedupe_key"]).returning(OutboundMessage.id))
    new_id = res.scalar()
    if new_id is None:
        return None
    return await db.get(OutboundMessage, new_id)


def get_template() -> str:
    from app.config import get_settings

    return get_settings().wa_template


async def deliver_due(db: AsyncSession, now: datetime, limit: int = 50, client=None) -> dict:
    """Send what is due. One message at a time; a failure is recorded and retried later (backoff), a permanent refusal is final."""
    stats = {"sent": 0, "failed": 0, "retry": 0, "held": 0}
    if not in_window(now):
        return {**stats, "held": 1}
    rows = (await db.scalars(
        select(OutboundMessage).where(OutboundMessage.status == "queued", OutboundMessage.next_attempt_at <= now).order_by(OutboundMessage.id).limit(limit).with_for_update(skip_locked=True)
    )).all()
    for m in rows:
        try:
            m.provider_id = await whatsapp.send_template(decrypt(m.to_phone_enc), list(m.params), client=client)
            m.status, m.sent_at = "sent", now
            stats["sent"] += 1
        except whatsapp.WhatsAppError as e:
            m.attempts += 1
            if e.permanent or m.attempts >= MAX_ATTEMPTS:
                m.status, m.detail = "failed", str(e)[:200]
                stats["failed"] += 1
            else:
                m.detail = str(e)[:200]
                m.next_attempt_at = now + timedelta(minutes=5 * 3 ** (m.attempts - 1))  # 5, 15, 45 minutes
                stats["retry"] += 1
    await db.commit()
    return stats


ORDER = {"queued": 0, "sent": 1, "delivered": 2, "read": 3}


async def apply_status(db: AsyncSession, provider_id: str, status: str, error: str | None = None) -> bool:
    """A delivery receipt from the webhook. Statuses only move forward (a late `sent` never undoes a `read`); `failed` always counts."""
    m = await db.scalar(select(OutboundMessage).where(OutboundMessage.provider_id == provider_id))
    if m is None:
        return False
    if status == "failed":
        m.status, m.detail = "failed", (error or "delivery failed")[:200]
    elif status in ORDER and ORDER.get(m.status, 0) < ORDER[status]:
        m.status = status
    await db.commit()
    return True


async def summary(db: AsyncSession, school_id: int) -> dict:
    rows = (await db.execute(select(OutboundMessage.status, OutboundMessage.kind).where(OutboundMessage.school_id == school_id))).all()
    out: dict[str, int] = defaultdict(int)
    for status, _ in rows:
        out[status] += 1
    return dict(out)
