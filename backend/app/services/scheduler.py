"""The background tick: deliver queued messages, and for schools that switched it on, plan reminders and hand the WhatsApp ones to the outbox.

One runner at a time across workers and containers (a Postgres advisory lock held on a dedicated connection)."""

import asyncio
import logging
from datetime import datetime

from sqlalchemy import func, select

from app import clock
from app.config import get_settings
from app.db import SessionLocal, engine
from app.models import AcademicYear, Reminder, School
from app.services import outbox, reminders

log = logging.getLogger("scolaris.scheduler")
LOCK_ID = 7240001


async def auto_reminders(db, now: datetime) -> int:
    """For each active school that opted in: plan today's reminders and queue the ones addressed to a parent on WhatsApp.
    Reminders for a phone call, and the escalation to the direction, stay for a person."""
    queued = 0
    for school in (await db.scalars(select(School).where(School.auto_whatsapp, School.status == "active"))).all():
        year = await db.scalar(select(AcademicYear).where(AcademicYear.school_id == school.id, AcademicYear.is_current))
        if year is None:
            continue
        await reminders.plan(db, school.id, year.id, now)
        for r in (await db.scalars(select(Reminder).where(Reminder.school_id == school.id, Reminder.status == "planned", Reminder.channel == "whatsapp"))).all():
            msg = await outbox.enqueue(db, school_id=school.id, family_id=r.family_id, kind="reminder", text=r.text, dedupe_key=f"reminder:{r.id}", now=now)
            r.status, r.sent_at = "sent", now  # handed to the outbox (sent_by stays empty: automatic)
            queued += int(msg is not None)
        await db.commit()
    return queued


async def tick(now: datetime | None = None, client=None) -> dict:
    now = now or clock.now()
    async with SessionLocal() as db:
        queued = await auto_reminders(db, now)
    async with SessionLocal() as db:
        stats = await outbox.deliver_due(db, now, client=client)
    return {"auto_queued": queued, **stats}


async def run_forever() -> None:
    seconds = get_settings().scheduler_seconds
    while True:
        try:
            async with engine.connect() as conn:  # the lock lives and dies with this connection
                if await conn.scalar(select(func.pg_try_advisory_lock(LOCK_ID))):
                    try:
                        log.info("tick %s", await tick())
                    finally:
                        await conn.scalar(select(func.pg_advisory_unlock(LOCK_ID)))
        except Exception:  # noqa: BLE001: a failing tick must never stop the loop
            log.exception("scheduler tick failed")
        await asyncio.sleep(seconds)
