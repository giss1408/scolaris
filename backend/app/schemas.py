from datetime import date
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.levels import ALL_LEVELS, DISCOUNT_KINDS, FEE_KINDS, PAYMENT_METHODS

Level = Literal[tuple(ALL_LEVELS)]  # type: ignore[valid-type]
FeeKind = Literal[tuple(FEE_KINDS)]  # type: ignore[valid-type]
Method = Literal[tuple(PAYMENT_METHODS)]  # type: ignore[valid-type]
DiscountKind = Literal[tuple(DISCOUNT_KINDS)]  # type: ignore[valid-type]


class YearIn(BaseModel):
    label: str = Field(pattern=r"^\d{4}-\d{4}$")
    starts_on: date
    ends_on: date
    is_current: bool = True


class ClassroomIn(BaseModel):
    year_id: int
    level: Level
    series: str | None = Field(default=None, max_length=4)
    name: str = Field(min_length=1, max_length=40)
    capacity: int | None = Field(default=None, ge=1, le=200)


class ContactIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    relation: Literal["pere", "mere", "tuteur", "autre"] = "autre"
    phone: str
    preferred_channel: Literal["whatsapp", "sms", "appel"] = "whatsapp"
    whatsapp_optin: bool = False
    financial_responsible: bool = False


class EnrollIn(BaseModel):
    classroom_id: int
    options: list[FeeKind] = []


class StudentIn(BaseModel):
    last_name: str = Field(min_length=1, max_length=80)
    first_names: str = Field(min_length=1, max_length=120)
    sex: Literal["M", "F"]
    birth_date: date | None = None
    birth_place: str | None = Field(default=None, max_length=80)
    matricule_mena: str | None = Field(default=None, max_length=20)
    assigned: bool = False
    family_id: int | None = None  # join an existing family (siblings); otherwise a new one is created
    contacts: list[ContactIn] = []
    enrollment: EnrollIn

    @field_validator("matricule_mena")
    @classmethod
    def _blank(cls, v: str | None) -> str | None:
        return (v or "").strip().upper() or None


class FeeLineIn(BaseModel):
    kind: FeeKind
    label: str = Field(min_length=1, max_length=80)
    amount: int = Field(gt=0, le=100_000_000)
    due_date: date
    optional: bool = False
    applies_to: Literal["all", "assigned", "non_assigned"] = "all"


class FeeScheduleIn(BaseModel):
    """Replaces the whole schedule of one level for one year (what the school really edits: the list of lines)."""

    year_id: int
    level: Level
    lines: list[FeeLineIn]


class PaymentIn(BaseModel):
    amount: int = Field(gt=0, le=100_000_000)
    method: Method
    reference: str | None = Field(default=None, max_length=80)
    idempotency_key: str | None = Field(default=None, min_length=8, max_length=64)


class VoidIn(BaseModel):
    reason: str = Field(min_length=3, max_length=240)


class DiscountIn(BaseModel):
    kind: DiscountKind
    amount: int = Field(gt=0, le=100_000_000)
    reason: str = Field(min_length=3, max_length=240)


class StaffIn(BaseModel):
    display_name: str = Field(min_length=2, max_length=120)
    phone: str
    role: Literal["accountant", "secretary"]  # the director is created by the platform team, not by herself
