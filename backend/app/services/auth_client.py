"""The calls this product makes back to the platform `auth` service, with its service key. Never logs a phone number or a key."""

import logging
import uuid

import httpx

from app.config import get_settings
from app.errors import BadRequest, Conflict, Unavailable

log = logging.getLogger("scolaris.auth")


def _client() -> httpx.AsyncClient:
    s = get_settings()
    return httpx.AsyncClient(base_url=s.auth_url, headers={"X-Service-Key": s.service_key}, timeout=8)


async def enrol_staff(*, phone: str, display_name: str, role: str) -> uuid.UUID:
    """Enrol one staff member at auth (pending account; the team sends the WhatsApp activation code). Returns her global user id."""
    s = get_settings()
    if not s.auth_url or not s.service_key:
        raise Unavailable("auth_not_configured")
    try:
        async with _client() as c:
            r = await c.post("/v1/service/staff", json={"phone": phone, "display_name": display_name, "role": role, "allow_existing": False})
    except httpx.HTTPError:
        raise Unavailable("auth_unreachable") from None
    if r.status_code == 409:
        raise Conflict("phone_taken")
    if r.status_code >= 400:
        log.warning("auth refused the enrolment (status %s)", r.status_code)
        raise BadRequest("auth_refused")
    return uuid.UUID(r.json()["user_id"])


async def remove_staff(user_id: uuid.UUID) -> None:
    """Take the role away at auth. Best effort: the local deactivation already blocks her, this just closes the account."""
    s = get_settings()
    if not s.auth_url or not s.service_key:
        return
    try:
        async with _client() as c:
            await c.delete(f"/v1/service/staff/{user_id}")
    except httpx.HTTPError:
        log.warning("auth unreachable while removing a staff account")


async def session_active(sid: str) -> bool:
    """Is the auth session still alive? Fails closed: an unreachable auth means NO for money actions."""
    s = get_settings()
    if not s.auth_url or not s.service_key:
        return False
    try:
        async with _client() as c:
            r = await c.post("/v1/sessions/check", json={"sid": sid})
        return r.status_code == 200 and bool(r.json().get("active"))
    except httpx.HTTPError:
        return False
