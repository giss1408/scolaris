"""Reminders for late payments: the scenario, the sending rules, one message per family.

The scenario (paramétrable later): J-5 courteous reminder, J+3 first late reminder, J+10 second with an instalment plan offer, J+20 invitation to
the economat, then ESCALATION to the direction (never an automatic measure against the pupil: that is a human decision).

Rules enforced here: nothing planned on Sunday; at most one reminder per family per 7 days; stops as soon as nothing is overdue any more
(payment recorded); a family with an open promise to pay is left alone until the promised date; the same (family, step, oldest due date) is
never planned twice (unique key + ON CONFLICT). Sending itself is done by a person through a prepared wa.me link (the platform has no
WhatsApp Business API yet): `mark_sent` records it. The 7:00-20:00 window is reported to the person (`can_send_now`), not enforced here.
"""

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from urllib.parse import quote

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Classroom, Contact, Enrollment, Family, FeeInstallment, PaymentPromise, Reminder, School, Student
from app.security import decrypt
from app.services import finance
from app.services.billing import Line, build_account

SEND_FROM, SEND_UNTIL = 7, 20  # local hours; Abidjan is UTC+0, no daylight saving
LATE_STEPS = [(30, "escalate"), (20, "late_20"), (10, "late_10"), (3, "late_3")]
BEFORE_DAYS = 5


@dataclass
class FamilyLine:
    enrollment_id: int
    student_name: str
    classroom: str
    line: Line


def step_for(lines: list[FamilyLine], today: date) -> tuple[str, date] | None:
    """The one step the family is at today and its anchor (due date of the oldest line behind it), or None."""
    late = [fl for fl in lines if fl.line.late_days > 0]
    if late:
        oldest = max(late, key=lambda fl: fl.line.late_days)
        for days, step in LATE_STEPS:
            if oldest.line.late_days >= days:
                return step, oldest.line.due_date
        return None  # late by 1-2 days: grace period, no message yet
    soon = [fl for fl in lines if 0 <= (fl.line.due_date - today).days <= BEFORE_DAYS and fl.line.remaining > 0]
    if soon:
        return "before", min(fl.line.due_date for fl in soon)
    return None


def money(n: int) -> str:
    return f"{n:,}".replace(",", " ") + " FCFA"


def compose(step: str, *, parent: str, school: str, lines: list[FamilyLine], phone: str | None) -> tuple[str, int]:
    """Polite, short, non-threatening, with a way to pay and a human contact. Returns (text, amount)."""
    if step == "before":
        target = sorted((fl for fl in lines if fl.line.late_days == 0 and fl.line.remaining > 0), key=lambda fl: fl.line.due_date)
        first = target[0].line.due_date
        target = [fl for fl in target if fl.line.due_date == first]
    else:
        target = [fl for fl in lines if fl.line.late_days > 0]
    amount = sum(fl.line.remaining for fl in target)
    kids = {}
    for fl in target:
        kids.setdefault(fl.student_name, fl.classroom)
    who = " et ".join(f"{n} ({c})" for n, c in kids.items())
    tranche = target[0].line.label
    call = f" ou appelez le {phone}" if phone else ""
    if step == "before":
        text = (f"Bonjour {parent}, l'école {school} vous rappelle que la {tranche} de {who}, d'un montant de {money(amount)}, "
                f"est attendue au plus tard le {target[0].line.due_date.strftime('%d/%m/%Y')}. Vous pouvez payer au guichet de l'école, par Wave ou Mobile Money. Merci de votre confiance.")
    elif step == "late_3":
        text = (f"Bonjour {parent}, sauf erreur de notre part, la {tranche} de {who} ({money(amount)}) n'est pas encore réglée. "
                f"Vous pouvez payer au guichet de l'école, par Wave ou Mobile Money. Si vous avez déjà payé, merci de ne pas tenir compte de ce message.")
    elif step == "late_10":
        text = (f"Bonjour {parent}, il reste {money(amount)} à régler pour {who}. Si vous rencontrez une difficulté, l'économat de {school} peut vous proposer "
                f"un échéancier. Répondez à ce message{call}.")
    elif step == "late_20":
        text = (f"Bonjour {parent}, nous aimerions vous rencontrer à l'économat de {school} au sujet de la scolarité de {who} ({money(amount)} restants). "
                f"Quand pouvez-vous passer cette semaine ? Répondez à ce message{call}.")
    else:  # escalate: for the direction, not for the parent
        text = f"Famille {parent} : {money(amount)} en retard pour {who}, relancée sans paiement. La direction décide de la suite."
    return text, amount


async def family_lines(db: AsyncSession, school_id: int, year_id: int, today: date) -> dict[int, list[FamilyLine]]:
    """Unpaid lines of the active enrolments of the year, per family."""
    rows = (await db.execute(
        select(Enrollment, Student, Classroom).join(Student, Student.id == Enrollment.student_id).join(Classroom, Classroom.id == Enrollment.classroom_id)
        .where(Enrollment.school_id == school_id, Enrollment.year_id == year_id, Enrollment.status == "active")
    )).all()
    if not rows:
        return {}
    fees = list((await db.scalars(select(FeeInstallment).where(FeeInstallment.school_id == school_id, FeeInstallment.year_id == year_id))).all())
    credits = await finance._credits(db, school_id, [r[0].id for r in rows])
    out: dict[int, list[FamilyLine]] = defaultdict(list)
    for enr, st, room in rows:
        acct = build_account(finance._dues_for(enr, st, room.level, fees), credits.get(enr.id, 0), today)
        for ln in acct.lines:
            if ln.remaining > 0:
                out[st.family_id].append(FamilyLine(enr.id, f"{st.first_names} {st.last_name}", room.name, ln))
    return out


def pick_contact(contacts: list[Contact]) -> tuple[Contact | None, str]:
    """The responsible parent first. WhatsApp only with her opt-in; otherwise her preferred channel; otherwise a phone call."""
    if not contacts:
        return None, "appel"
    c = sorted(contacts, key=lambda c: (not c.financial_responsible, c.id))[0]
    if c.whatsapp_optin_at is not None and c.preferred_channel == "whatsapp":
        return c, "whatsapp"
    return c, "sms" if c.preferred_channel == "sms" else "appel"


async def plan(db: AsyncSession, school_id: int, year_id: int, now: datetime) -> dict:
    today = now.date()
    stats = {"planned": 0, "skipped_stale": 0}
    school = await db.get(School, school_id)
    fam_lines = await family_lines(db, school_id, year_id, today)

    # a payment stops the reminders: planned ones whose family has nothing to chase any more are dropped
    pending = list((await db.scalars(select(Reminder).where(Reminder.school_id == school_id, Reminder.status == "planned"))).all())
    for r in pending:
        if step_for(fam_lines.get(r.family_id, []), today) is None:
            r.status = "skipped"
            stats["skipped_stale"] += 1
    await db.flush()
    if today.weekday() == 6:  # Sunday: nothing new
        await db.commit()
        return stats

    recent_sent = {r.family_id for r in (await db.scalars(select(Reminder).where(
        Reminder.school_id == school_id, Reminder.status == "sent", Reminder.sent_at >= now - timedelta(days=7), Reminder.channel != "direction"))).all()}
    open_now = {r.family_id for r in pending if r.status == "planned"}
    promises = (await db.scalars(select(PaymentPromise).where(PaymentPromise.school_id == school_id, PaymentPromise.status == "open"))).all()
    promise_until: dict[int, date] = {}
    for p in promises:
        if p.promised_for >= today:
            promise_until[p.family_id] = max(promise_until.get(p.family_id, p.promised_for), p.promised_for)
        elif p.family_id in fam_lines and any(fl.line.late_days > 0 for fl in fam_lines[p.family_id]):
            p.status = "broken"  # the date passed and it is still late: reminders resume

    families = {f.id: f for f in (await db.scalars(select(Family).where(Family.school_id == school_id, Family.id.in_(list(fam_lines))))).all()} if fam_lines else {}
    contacts_by: dict[int, list[Contact]] = defaultdict(list)
    if fam_lines:
        for c in await db.scalars(select(Contact).where(Contact.school_id == school_id, Contact.family_id.in_(list(fam_lines)))):
            contacts_by[c.family_id].append(c)

    for fid, lines in fam_lines.items():
        st = step_for(lines, today)
        if st is None or fid in promise_until or fid in open_now:
            continue
        step, anchor = st
        if step != "escalate" and fid in recent_sent:
            continue  # at most one reminder per family per week
        contact, channel = pick_contact(contacts_by.get(fid, []))
        if step == "escalate":
            channel = "direction"
        text, amount = compose(step, parent=(contact.name if contact else families[fid].name), school=school.name, lines=lines, phone=school.phone)
        res = await db.execute(pg_insert(Reminder).values(school_id=school_id, family_id=fid, step=step, anchor=anchor, channel=channel, amount=amount, text=text, planned_on=today)
                               .on_conflict_do_nothing(index_elements=["family_id", "step", "anchor"]))
        stats["planned"] += res.rowcount or 0
    await db.commit()
    return stats


def wa_link(phone: str, text: str) -> str:
    return f"https://wa.me/{phone.lstrip('+')}?text={quote(text)}"


async def due_list(db: AsyncSession, school_id: int, now: datetime, include_direction: bool) -> list[dict]:
    rows = (await db.scalars(select(Reminder).where(Reminder.school_id == school_id, Reminder.status == "planned").order_by(Reminder.amount.desc()))).all()
    if not rows:
        return []
    fams = {f.id: f for f in await db.scalars(select(Family).where(Family.id.in_([r.family_id for r in rows])))}
    contacts: dict[int, list[Contact]] = defaultdict(list)
    for c in await db.scalars(select(Contact).where(Contact.family_id.in_(list(fams)))):
        contacts[c.family_id].append(c)
    in_window = now.weekday() != 6 and SEND_FROM <= now.hour < SEND_UNTIL
    out = []
    for r in rows:
        if r.channel == "direction" and not include_direction:
            continue
        contact, _ = pick_contact(contacts.get(r.family_id, []))
        phone = decrypt(contact.phone_enc) if contact else None
        out.append({
            "id": r.id, "family_id": r.family_id, "family_name": fams[r.family_id].name, "step": r.step, "channel": r.channel, "amount": r.amount, "text": r.text,
            "contact_name": contact.name if contact else None, "phone": phone, "can_send_now": in_window,
            "wa_link": wa_link(phone, r.text) if phone and r.channel == "whatsapp" else None,
        })
    return out


async def mark_sent(db: AsyncSession, school_id: int, reminder_id: int, staff_id: int, now: datetime) -> bool:
    """Idempotent: a second tap changes nothing."""
    res = await db.execute(update(Reminder).where(Reminder.id == reminder_id, Reminder.school_id == school_id, Reminder.status == "planned").values(status="sent", sent_at=now, sent_by=staff_id))
    await db.commit()
    return bool(res.rowcount)
