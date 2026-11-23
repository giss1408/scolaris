"""Who is calling: a verified `auth` token mapped to an active staff member of ONE school. Every query is then filtered by `me.school_id`."""

from dataclasses import dataclass
from functools import lru_cache

import httpx
from anyio import to_thread
from fastapi import Depends, Header, Request
from regisse_kit.sso import Principal, SsoError, SsoVerifier
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_session
from app.errors import Forbidden, Unauthorized
from app.models import StaffMember
from app.services import auth_client


@lru_cache
def verifier() -> SsoVerifier:
    s = get_settings()
    return SsoVerifier(issuer=s.sso_issuer, audience=s.sso_audience, jwks_fetch=lambda: httpx.get(s.sso_jwks_url, timeout=5).raise_for_status().json())


def reset_verifier() -> None:
    verifier.cache_clear()


@dataclass
class Me:
    staff: StaffMember
    principal: Principal

    @property
    def school_id(self) -> int:
        return self.staff.school_id

    @property
    def role(self) -> str:
        return self.staff.role

    def require_role(self, *roles: str) -> "Me":
        if self.staff.role not in roles:
            raise Forbidden("forbidden_role")
        return self

    async def require_recent_password(self) -> None:
        """Sensitive money actions: the password was re-proved a few minutes ago AND the auth session is still alive."""
        try:
            self.principal.require_step_up(get_settings().step_up_seconds, amr="pwd")
        except SsoError:
            raise Forbidden("step_up_required") from None
        if not await auth_client.session_active(self.principal.sid):
            raise Forbidden("session_ended")


# A blocked school keeps only what its direction needs to understand and settle the situation.
ALLOWED_WHEN_BLOCKED = ("/v1/me", "/v1/billing", "/v1/school/logo")


async def current_me(request: Request, authorization: str | None = Header(default=None), db: AsyncSession = Depends(get_session)) -> Me:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise Unauthorized("missing_token")
    token = authorization[7:].strip()
    try:
        p = await to_thread.run_sync(verifier().verify, token)
    except (SsoError, httpx.HTTPError, ValueError):
        raise Unauthorized("invalid_token") from None
    if p.app != "staff":
        raise Forbidden("wrong_app")
    if p.must_change_password:
        raise Forbidden("password_change_required")
    import uuid

    try:
        uid = uuid.UUID(p.sub)
    except ValueError:
        raise Unauthorized("invalid_token") from None
    staff = await db.scalar(select(StaffMember).where(StaffMember.auth_user_id == uid))
    # An unknown or deactivated person is refused even with a valid token; her role must match what auth says she holds.
    if staff is None or not staff.active or staff.role != p.role:
        raise Forbidden("not_staff")
    from app.models import School

    school = await db.get(School, staff.school_id)
    if school.status == "blocked":
        path = request.url.path
        if staff.role not in ("director", "secretary") or not any(path == a or path.startswith(a + "/") for a in ALLOWED_WHEN_BLOCKED):
            raise Forbidden("school_blocked", "L'accès de votre établissement est suspendu. Contactez la direction.")
    return Me(staff=staff, principal=p)


@dataclass
class ParentMe:
    """A parent signed in at auth (app `parent`). She is identified by her verified phone number: the contacts the school recorded
    with the SAME number are hers, in every school that has her. She sees her own children only."""

    principal: Principal
    contact_ids: list[int]
    family_ids: list[int]
    phone_hash: str


async def current_parent(authorization: str | None = Header(default=None), db: AsyncSession = Depends(get_session)) -> ParentMe:
    from app.models import Contact
    from app.security import phone_hash as _hash

    if not authorization or not authorization.lower().startswith("bearer "):
        raise Unauthorized("missing_token")
    try:
        p = await to_thread.run_sync(verifier().verify, authorization[7:].strip())
    except (SsoError, httpx.HTTPError, ValueError):
        raise Unauthorized("invalid_token") from None
    if p.app != "parent" or p.role != "parent":
        raise Forbidden("wrong_app")
    if p.must_change_password:
        raise Forbidden("password_change_required")
    if not p.phone_key.startswith("tel:+"):
        raise Forbidden("no_phone")
    h = _hash(p.phone_key[4:])
    rows = (await db.execute(select(Contact.id, Contact.family_id).where(Contact.phone_hash == h))).all()
    return ParentMe(principal=p, contact_ids=[r[0] for r in rows], family_ids=sorted({r[1] for r in rows}), phone_hash=h)


@dataclass
class AdminMe:
    """A member of the Scolaris team: signed in at auth in the `admin` app, with her authenticator code. Not a member of any school."""

    principal: Principal

    @property
    def id(self) -> str:
        return self.principal.sub

    async def require_recent_password(self) -> None:
        """Blocking a school, taking a payment: the password was re-proved a few minutes ago AND the auth session is still alive."""
        try:
            self.principal.require_step_up(get_settings().step_up_seconds, amr="pwd")
        except SsoError:
            raise Forbidden("step_up_required") from None
        if not await auth_client.session_active(self.principal.sid):
            raise Forbidden("session_ended")


async def current_admin(authorization: str | None = Header(default=None)) -> AdminMe:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise Unauthorized("missing_token")
    try:
        p = await to_thread.run_sync(verifier().verify, authorization[7:].strip())
    except (SsoError, httpx.HTTPError, ValueError):
        raise Unauthorized("invalid_token") from None
    if p.app != get_settings().admin_audience_app or p.role != "platform_admin":
        raise Forbidden("not_platform_admin")
    if "totp" not in p.amr:  # the authenticator code is part of this role's sign-in; a token without it is refused
        raise Forbidden("totp_required")
    if p.must_change_password:
        raise Forbidden("password_change_required")
    return AdminMe(principal=p)
