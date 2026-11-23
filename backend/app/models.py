"""Scolaris data model. Every row belongs to one school (`school_id`): isolation is enforced in the queries (see deps.py / services).

Money is an integer number of FCFA (XOF has no decimals). Nothing financial is ever deleted: a cancelled payment is
a credit note (avoir) that points back at it.
"""

import uuid
from datetime import date, datetime, time

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    String,
    Text,
    Time,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def _now() -> datetime:
    return datetime.now().astimezone()


class School(Base):
    __tablename__ = "school"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(160))
    # public | prive_laic | prive_confessionnel
    kind: Mapped[str] = mapped_column(String(24), default="prive_laic")
    code_mena: Mapped[str | None] = mapped_column(String(40))
    city: Mapped[str | None] = mapped_column(String(80))
    phone: Mapped[str | None] = mapped_column(String(20))  # the school's economat line, quoted in reminders
    # send reminders and notices to families by WhatsApp on its own (default off: the school opts in)
    auto_whatsapp: Mapped[bool] = mapped_column(Boolean, default=False)
    logo: Mapped[bytes | None] = mapped_column(LargeBinary)  # the school's logo (PNG or JPEG, small), shown in the app and on documents
    logo_type: Mapped[str | None] = mapped_column(String(20))
    # the Scolaris team can block a school that is late with its monthly subscription (after reminders): staff and parents are then refused
    status: Mapped[str] = mapped_column(String(10), default="active")  # active | blocked
    blocked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    blocked_reason: Mapped[str | None] = mapped_column(String(240))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    # honours thresholds override (see levels.DEFAULT_HONOURS), e.g. {"felicitations": 15}
    honour_thresholds: Mapped[dict | None] = mapped_column(JSONB)


class StaffMember(Base):
    """A person of the school's staff. `auth_user_id` is the opaque global id from the `auth` service (no phone is kept here)."""

    __tablename__ = "staff_member"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    auth_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), unique=True)
    display_name: Mapped[str] = mapped_column(String(120))
    role: Mapped[str] = mapped_column(String(20))  # director | accountant | secretary | teacher
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class AcademicYear(Base):
    __tablename__ = "academic_year"
    __table_args__ = (UniqueConstraint("school_id", "label"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    label: Mapped[str] = mapped_column(String(20))  # "2026-2027"
    starts_on: Mapped[date] = mapped_column(Date)
    ends_on: Mapped[date] = mapped_column(Date)
    is_current: Mapped[bool] = mapped_column(Boolean, default=False)


class Classroom(Base):
    __tablename__ = "classroom"
    __table_args__ = (UniqueConstraint("school_id", "year_id", "name"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    year_id: Mapped[int] = mapped_column(ForeignKey("academic_year.id"), index=True)
    level: Mapped[str] = mapped_column(String(10))  # CP1 ... CM2, 6e ... Tle (see app/levels.py)
    series: Mapped[str | None] = mapped_column(String(4))
    name: Mapped[str] = mapped_column(String(40))  # "6e 2"
    capacity: Mapped[int | None] = mapped_column(Integer)
    # the "professeur principal": sees the whole class report cards and writes conduct and appreciation
    head_teacher_id: Mapped[int | None] = mapped_column(ForeignKey("staff_member.id"))


class Family(Base):
    """Groups siblings: one family, one message, one financial summary."""

    __tablename__ = "family"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    contacts: Mapped[list["Contact"]] = relationship(back_populates="family", order_by="Contact.id")


class Contact(Base):
    __tablename__ = "contact"
    __table_args__ = (UniqueConstraint("family_id", "phone_hash"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    family_id: Mapped[int] = mapped_column(ForeignKey("family.id"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    relation: Mapped[str] = mapped_column(String(20))  # pere | mere | tuteur | autre
    phone_enc: Mapped[bytes] = mapped_column(LargeBinary)  # E.164, AES-GCM
    phone_hash: Mapped[str] = mapped_column(String(64), index=True)  # keyed hash, for lookups
    preferred_channel: Mapped[str] = mapped_column(String(10), default="whatsapp")  # whatsapp | sms | appel
    whatsapp_optin_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    financial_responsible: Mapped[bool] = mapped_column(Boolean, default=False)
    family: Mapped[Family] = relationship(back_populates="contacts")


class Student(Base):
    __tablename__ = "student"
    __table_args__ = (
        UniqueConstraint("school_id", "matricule_mena"),
        UniqueConstraint("school_id", "internal_number"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    family_id: Mapped[int] = mapped_column(ForeignKey("family.id"), index=True)
    internal_number: Mapped[str] = mapped_column(String(20))
    matricule_mena: Mapped[str | None] = mapped_column(String(20))  # national id, unique when given
    last_name: Mapped[str] = mapped_column(String(80))
    first_names: Mapped[str] = mapped_column(String(120))
    sex: Mapped[str] = mapped_column(String(1))  # M | F
    birth_date: Mapped[date | None] = mapped_column(Date)
    birth_place: Mapped[str | None] = mapped_column(String(80))
    nationality: Mapped[str | None] = mapped_column(String(40), default="Ivoirienne")
    assigned: Mapped[bool] = mapped_column(Boolean, default=False)  # "affecté" by the State (changes the fees due)
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    family: Mapped[Family] = relationship()


class Enrollment(Base):
    __tablename__ = "enrollment"
    __table_args__ = (UniqueConstraint("student_id", "year_id"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("student.id"), index=True)
    classroom_id: Mapped[int] = mapped_column(ForeignKey("classroom.id"), index=True)
    year_id: Mapped[int] = mapped_column(ForeignKey("academic_year.id"), index=True)
    status: Mapped[str] = mapped_column(String(12), default="active")  # active | withdrawn
    options: Mapped[list[str]] = mapped_column(ARRAY(String(20)), default=list)  # optional fee kinds taken (cantine, transport...)
    enrolled_on: Mapped[date] = mapped_column(Date, default=date.today)
    student: Mapped[Student] = relationship()
    classroom: Mapped[Classroom] = relationship()


class FeeInstallment(Base):
    """One line of the fee schedule of a level for a year: what is due, how much, by when. The price list IS the schedule."""

    __tablename__ = "fee_installment"
    __table_args__ = (CheckConstraint("amount > 0"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    year_id: Mapped[int] = mapped_column(ForeignKey("academic_year.id"), index=True)
    level: Mapped[str] = mapped_column(String(10))
    kind: Mapped[str] = mapped_column(String(20))  # inscription | scolarite | cantine | transport | coges ...
    label: Mapped[str] = mapped_column(String(80))  # "1re tranche"
    amount: Mapped[int] = mapped_column(BigInteger)
    due_date: Mapped[date] = mapped_column(Date)
    optional: Mapped[bool] = mapped_column(Boolean, default=False)
    applies_to: Mapped[str] = mapped_column(String(12), default="all")  # all | assigned | non_assigned


class Discount(Base):
    """A reduction granted to one enrolment (sibling, staff child, scholarship...). It is credited like a payment (oldest due first),
    but it is not cash and has no receipt. Validated by a named person with a reason."""

    __tablename__ = "discount"
    __table_args__ = (CheckConstraint("amount > 0"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    enrollment_id: Mapped[int] = mapped_column(ForeignKey("enrollment.id"), index=True)
    kind: Mapped[str] = mapped_column(String(20))  # fratrie | personnel | bourse | exceptionnelle
    amount: Mapped[int] = mapped_column(BigInteger)
    reason: Mapped[str] = mapped_column(String(240))
    granted_by: Mapped[int] = mapped_column(ForeignKey("staff_member.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Payment(Base):
    """A cash-in (`payment`) or its cancellation (`credit_note`, negative amount, `reverses_id` = the payment it cancels)."""

    __tablename__ = "payment"
    __table_args__ = (
        UniqueConstraint("school_id", "receipt_number"),
        UniqueConstraint("school_id", "idempotency_key"),
        UniqueConstraint("reverses_id"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    enrollment_id: Mapped[int] = mapped_column(ForeignKey("enrollment.id"), index=True)
    kind: Mapped[str] = mapped_column(String(12), default="payment")  # payment | credit_note
    amount: Mapped[int] = mapped_column(BigInteger)  # > 0 for a payment, < 0 for a credit note
    method: Mapped[str] = mapped_column(String(16))  # especes | wave | orange_money | mtn_momo | moov_money | virement | cheque
    reference: Mapped[str | None] = mapped_column(String(80))  # operator transaction id, cheque number...
    receipt_number: Mapped[str] = mapped_column(String(32))
    reverses_id: Mapped[int | None] = mapped_column(ForeignKey("payment.id"))
    reason: Mapped[str | None] = mapped_column(String(240))
    cashier_id: Mapped[int] = mapped_column(ForeignKey("staff_member.id"))
    idempotency_key: Mapped[str | None] = mapped_column(String(64))  # an app that retries after a timeout never records twice
    paid_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now, index=True)


class ReceiptCounter(Base):
    """Gapless sequence per school, year and kind (receipt `REC`, credit note `AV`). Locked FOR UPDATE when a number is taken."""

    __tablename__ = "receipt_counter"
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), primary_key=True)
    year_id: Mapped[int] = mapped_column(ForeignKey("academic_year.id"), primary_key=True)
    prefix: Mapped[str] = mapped_column(String(4), primary_key=True)
    last: Mapped[int] = mapped_column(Integer, default=0)


class AuditLog(Base):
    __tablename__ = "audit_log"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int | None] = mapped_column(ForeignKey("school.id"), index=True)
    actor_id: Mapped[int | None] = mapped_column(ForeignKey("staff_member.id"))
    action: Mapped[str] = mapped_column(String(40))
    entity: Mapped[str] = mapped_column(String(30))
    entity_id: Mapped[int | None] = mapped_column(BigInteger)
    detail: Mapped[dict] = mapped_column(JSONB, default=dict)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Subject(Base):
    __tablename__ = "subject"
    __table_args__ = (UniqueConstraint("school_id", "name"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    name: Mapped[str] = mapped_column(String(60))


class Coefficient(Base):
    """Weight of a subject for a level in a year. A coefficient of 0 means the subject is shown but not counted."""

    __tablename__ = "coefficient"
    __table_args__ = (UniqueConstraint("school_id", "year_id", "level", "subject_id"), CheckConstraint("coef >= 0 AND coef <= 20"))
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    year_id: Mapped[int] = mapped_column(ForeignKey("academic_year.id"), index=True)
    level: Mapped[str] = mapped_column(String(10))
    subject_id: Mapped[int] = mapped_column(ForeignKey("subject.id"))
    coef: Mapped[int] = mapped_column(Integer)


class Evaluation(Base):
    """A test (devoir, interrogation, composition) given to one class in one subject for one period. Locked once validated."""

    __tablename__ = "evaluation"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    classroom_id: Mapped[int] = mapped_column(ForeignKey("classroom.id"), index=True)
    subject_id: Mapped[int] = mapped_column(ForeignKey("subject.id"))
    period: Mapped[int] = mapped_column(Integer)
    kind: Mapped[str] = mapped_column(String(14))
    title: Mapped[str | None] = mapped_column(String(80))
    held_on: Mapped[date] = mapped_column(Date, default=date.today)
    max_score: Mapped[int] = mapped_column(Integer, default=20)  # 20 (10 allowed in primary): normalised to /20 for averages
    created_by: Mapped[int] = mapped_column(ForeignKey("staff_member.id"))
    locked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Grade(Base):
    __tablename__ = "grade"
    __table_args__ = (UniqueConstraint("evaluation_id", "enrollment_id"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    evaluation_id: Mapped[int] = mapped_column(ForeignKey("evaluation.id", ondelete="CASCADE"), index=True)
    enrollment_id: Mapped[int] = mapped_column(ForeignKey("enrollment.id"), index=True)
    value: Mapped[float | None] = mapped_column(Numeric(5, 2))  # None with absent = true: not counted (never a zero)
    absent: Mapped[bool] = mapped_column(Boolean, default=False)


class Absence(Base):
    """A day-level absence (slot matin/soir/jour, `slot_id` NULL) or one noted during a COURSE (`slot_id` = the timetable period)."""

    __tablename__ = "absence"
    __table_args__ = (
        Index("uq_absence_day", "enrollment_id", "day", "slot", unique=True, postgresql_where=text("slot_id IS NULL")),
        Index("uq_absence_course", "enrollment_id", "day", "slot_id", unique=True, postgresql_where=text("slot_id IS NOT NULL")),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    enrollment_id: Mapped[int] = mapped_column(ForeignKey("enrollment.id"), index=True)
    day: Mapped[date] = mapped_column(Date)
    slot: Mapped[str] = mapped_column(String(8), default="jour")  # matin | soir | jour
    kind: Mapped[str] = mapped_column(String(8), default="absence")  # absence | retard
    justified: Mapped[bool] = mapped_column(Boolean, default=False)
    reason: Mapped[str | None] = mapped_column(String(160))
    recorded_by: Mapped[int] = mapped_column(ForeignKey("staff_member.id"))
    slot_id: Mapped[int | None] = mapped_column(ForeignKey("timetable_slot.id", ondelete="SET NULL"), index=True)


class PeriodRemark(Base):
    """What the report card carries besides marks: conduct, the teacher's appreciation, and (last period) the council's decision."""

    __tablename__ = "period_remark"
    __table_args__ = (UniqueConstraint("enrollment_id", "period"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    enrollment_id: Mapped[int] = mapped_column(ForeignKey("enrollment.id"), index=True)
    period: Mapped[int] = mapped_column(Integer)
    conduct: Mapped[float | None] = mapped_column(Numeric(4, 2))  # /20
    appreciation: Mapped[str | None] = mapped_column(String(240))
    sanction: Mapped[str | None] = mapped_column(String(20))  # avertissement_travail | avertissement_conduite | blame
    decision: Mapped[str | None] = mapped_column(String(16))  # passage | redoublement | exclusion | reorientation (council, a human decision)


class PaymentPromise(Base):
    """A family's commitment to pay ("je paie le 15"): reminders pause until the promised date."""

    __tablename__ = "payment_promise"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    family_id: Mapped[int] = mapped_column(ForeignKey("family.id"), index=True)
    amount: Mapped[int] = mapped_column(BigInteger)
    promised_for: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(10), default="open")  # open | kept | broken
    recorded_by: Mapped[int] = mapped_column(ForeignKey("staff_member.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class Reminder(Base):
    """One message per FAMILY (all her children together) for one step of the scenario. UNIQUE (family, step, anchor): the same reminder
    is planned once, whatever the number of times the planner runs. `anchor` = due date of the oldest line that triggered it."""

    __tablename__ = "reminder"
    __table_args__ = (UniqueConstraint("family_id", "step", "anchor"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    family_id: Mapped[int] = mapped_column(ForeignKey("family.id"), index=True)
    step: Mapped[str] = mapped_column(String(16))  # before | late_3 | late_10 | late_20 | escalate
    anchor: Mapped[date] = mapped_column(Date)
    channel: Mapped[str] = mapped_column(String(10))  # whatsapp | sms | appel | direction
    status: Mapped[str] = mapped_column(String(10), default="planned")  # planned | sent | skipped
    amount: Mapped[int] = mapped_column(BigInteger)  # the family's overdue (or upcoming) total at planning time
    text: Mapped[str] = mapped_column(Text)
    planned_on: Mapped[date] = mapped_column(Date)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    sent_by: Mapped[int | None] = mapped_column(ForeignKey("staff_member.id"))


class TeacherAssignment(Base):
    """A teacher is linked to a class, for one subject or (subject_id NULL) for all the subjects she gives there. No assignment, no access."""

    __tablename__ = "teacher_assignment"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    staff_id: Mapped[int] = mapped_column(ForeignKey("staff_member.id"), index=True)
    classroom_id: Mapped[int] = mapped_column(ForeignKey("classroom.id", ondelete="CASCADE"), index=True)
    subject_id: Mapped[int | None] = mapped_column(ForeignKey("subject.id"))


class TimetableSlot(Base):
    """One period of the weekly timetable of a class. Weekday 1 = Monday ... 6 = Saturday. No overlap inside a class, for a teacher or in a room."""

    __tablename__ = "timetable_slot"
    __table_args__ = (CheckConstraint("weekday BETWEEN 1 AND 6"), CheckConstraint("end_time > start_time"))
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    classroom_id: Mapped[int] = mapped_column(ForeignKey("classroom.id", ondelete="CASCADE"), index=True)
    weekday: Mapped[int] = mapped_column(Integer)
    start_time: Mapped[time] = mapped_column(Time)
    end_time: Mapped[time] = mapped_column(Time)
    subject_id: Mapped[int] = mapped_column(ForeignKey("subject.id"))
    teacher_id: Mapped[int | None] = mapped_column(ForeignKey("staff_member.id"), index=True)
    room: Mapped[str | None] = mapped_column(String(30))


class SlotCancellation(Base):
    """One session of a timetable period that will not take place (a date). The period itself stays; reversible until the day has passed."""

    __tablename__ = "slot_cancellation"
    __table_args__ = (UniqueConstraint("slot_id", "on_date"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    slot_id: Mapped[int] = mapped_column(ForeignKey("timetable_slot.id", ondelete="CASCADE"), index=True)
    on_date: Mapped[date] = mapped_column(Date)
    reason: Mapped[str] = mapped_column(String(20))  # maladie | absence_autorisee | formation | autre (kept for the administration, NOT shown to parents)
    note: Mapped[str | None] = mapped_column(String(160))
    cancelled_by: Mapped[int] = mapped_column(ForeignKey("staff_member.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    # a replacement teacher for this session (assigned by the director or secretary): she sees the class that day and may call the roll
    substitute_staff_id: Mapped[int | None] = mapped_column(ForeignKey("staff_member.id"), index=True)


class AbsenceReport(Base):
    """A parent tells the school her child will be (or was) absent for a day. The school sees it in the roll call and decides to justify it."""

    __tablename__ = "absence_report"
    __table_args__ = (UniqueConstraint("enrollment_id", "day"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    enrollment_id: Mapped[int] = mapped_column(ForeignKey("enrollment.id"), index=True)
    day: Mapped[date] = mapped_column(Date)
    reason: Mapped[str] = mapped_column(String(20))  # maladie | rendez_vous | famille | autre
    note: Mapped[str | None] = mapped_column(String(160))
    contact_id: Mapped[int | None] = mapped_column(ForeignKey("contact.id"))  # which of her contacts reported (matched by phone)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class OutboundMessage(Base):
    """A WhatsApp message to a family: queued, sent, delivered, read or failed. UNIQUE (school, dedupe_key): the same notice is never queued twice."""

    __tablename__ = "outbound_message"
    __table_args__ = (UniqueConstraint("school_id", "dedupe_key"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    family_id: Mapped[int | None] = mapped_column(ForeignKey("family.id"), index=True)
    contact_id: Mapped[int | None] = mapped_column(ForeignKey("contact.id"))
    to_phone_enc: Mapped[bytes | None] = mapped_column(LargeBinary)  # E.164, AES-GCM (none when the family cannot be reached on WhatsApp)
    kind: Mapped[str] = mapped_column(String(16))  # reminder | absence | cancellation | substitute | other
    template: Mapped[str] = mapped_column(String(40))
    params: Mapped[list] = mapped_column(JSONB, default=list)
    preview: Mapped[str] = mapped_column(Text)  # what the family reads (for the school's message log)
    dedupe_key: Mapped[str] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(10), default="queued")  # queued | sent | delivered | read | failed | skipped
    detail: Mapped[str | None] = mapped_column(String(200))  # why skipped / failed
    provider_id: Mapped[str | None] = mapped_column(String(100), index=True)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    next_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Subscription(Base):
    """What a school owes Scolaris each month. One row per school; set by the platform team."""

    __tablename__ = "subscription"
    __table_args__ = (CheckConstraint("monthly_amount > 0 AND billing_day BETWEEN 1 AND 28"),)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), primary_key=True)
    monthly_amount: Mapped[int] = mapped_column(BigInteger)  # FCFA
    billing_day: Mapped[int] = mapped_column(Integer, default=5)  # day of the month the instalment is due
    grace_days: Mapped[int] = mapped_column(Integer, default=5)  # days after the due date before the school counts as late
    started_on: Mapped[date] = mapped_column(Date)
    updated_by: Mapped[str | None] = mapped_column(String(64))


class SubscriptionPayment(Base):
    __tablename__ = "subscription_payment"
    __table_args__ = (CheckConstraint("amount > 0"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    amount: Mapped[int] = mapped_column(BigInteger)
    method: Mapped[str] = mapped_column(String(16))
    reference: Mapped[str | None] = mapped_column(String(80))
    paid_on: Mapped[date] = mapped_column(Date)
    recorded_by: Mapped[str] = mapped_column(String(64))  # the platform admin's opaque user id at auth
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class SchoolNotice(Base):
    """A message from the Scolaris team to a school, shown to its director AND its secretary (reminders about the subscription, the block, its lifting)."""

    __tablename__ = "school_notice"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    kind: Mapped[str] = mapped_column(String(14))  # reminder | final_notice | blocked | unblocked | info
    title: Mapped[str] = mapped_column(String(120))
    text: Mapped[str] = mapped_column(Text)
    block_on: Mapped[date | None] = mapped_column(Date)  # final notice: the earliest date the school may be blocked
    created_by: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class SchoolNoticeSeen(Base):
    __tablename__ = "school_notice_seen"
    __table_args__ = (UniqueConstraint("notice_id", "staff_id"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    notice_id: Mapped[int] = mapped_column(ForeignKey("school_notice.id", ondelete="CASCADE"), index=True)
    staff_id: Mapped[int] = mapped_column(ForeignKey("staff_member.id"))
    seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class PlatformAudit(Base):
    """What the Scolaris team did to a school (subscription, notices, blocking). Never deleted."""

    __tablename__ = "platform_audit"
    id: Mapped[int] = mapped_column(primary_key=True)
    admin: Mapped[str] = mapped_column(String(64))
    school_id: Mapped[int | None] = mapped_column(ForeignKey("school.id"), index=True)
    action: Mapped[str] = mapped_column(String(40))
    detail: Mapped[dict] = mapped_column(JSONB, default=dict)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
