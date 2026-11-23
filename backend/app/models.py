"""Scolaris data model. Every row belongs to one school (`school_id`): isolation is enforced in the queries (see deps.py / services).

Money is an integer number of FCFA (XOF has no decimals). Nothing financial is ever deleted: a cancelled payment is
a credit note (avoir) that points back at it.
"""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    func,
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
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=_now)


class StaffMember(Base):
    """A person of the school's staff. `auth_user_id` is the opaque global id from the `auth` service (no phone is kept here)."""

    __tablename__ = "staff_member"
    id: Mapped[int] = mapped_column(primary_key=True)
    school_id: Mapped[int] = mapped_column(ForeignKey("school.id"), index=True)
    auth_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), unique=True)
    display_name: Mapped[str] = mapped_column(String(120))
    role: Mapped[str] = mapped_column(String(20))  # director | accountant | secretary
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
