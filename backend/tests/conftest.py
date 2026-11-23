import base64
import os
import time
import uuid
from collections.abc import AsyncIterator

os.environ.update({
    "SCO_ENV": "test",
    "SCO_SCHEDULER": "false",
    "SCO_DATABASE_URL": "postgresql+asyncpg://scolaris:scolaris@localhost:5440/scolaris_test",
    "SCO_FIELD_ENCRYPTION_KEY": base64.b64encode(b"e" * 32).decode(),
    "SCO_HASH_KEY": base64.b64encode(b"h" * 32).decode(),
    "SCO_SSO_ISSUER": "http://auth.test",
    "SCO_METRICS_TOKEN": "t" * 40,
})

import asyncpg  # noqa: E402
import jwt  # noqa: E402
import pytest  # noqa: E402
from cryptography.hazmat.primitives import serialization  # noqa: E402
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from regisse_kit.sso import SsoVerifier  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app import deps  # noqa: E402
from app.db import Base, SessionLocal, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import AcademicYear, StaffMember, School  # noqa: E402
from app.services import auth_client  # noqa: E402

_KEY = Ed25519PrivateKey.generate()
_PEM = _KEY.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
_X = base64.urlsafe_b64encode(_KEY.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).rstrip(b"=").decode()
JWKS = {"keys": [{"kty": "OKP", "crv": "Ed25519", "kid": "k1", "x": _X}]}


def make_token(user_id: uuid.UUID, role: str, *, app_name: str = "staff", amr=("pwd",), auth_time: float | None = None, mcp: bool = False, sid: str = "sid-12345678") -> str:
    now = int(time.time())
    claims = {"sub": str(user_id), "iss": "http://auth.test", "aud": "scolaris", "iat": now, "exp": now + 600, "sid": sid, "role": role, "roles": [role],
              "app": app_name, "amr": list(amr), "auth_time": int(auth_time if auth_time is not None else now), "ph": "tel:+22507", "mcp": mcp}
    return jwt.encode(claims, _PEM, algorithm="EdDSA", headers={"kid": "k1"})


@pytest.fixture(scope="session", autouse=True)
def _create_test_db() -> None:
    import asyncio

    async def setup() -> None:
        conn = await asyncpg.connect("postgresql://scolaris:scolaris@localhost:5440/scolaris")
        await conn.execute("DROP DATABASE IF EXISTS scolaris_test WITH (FORCE)")
        await conn.execute("CREATE DATABASE scolaris_test")
        await conn.close()
        async with engine.begin() as c:
            await c.run_sync(Base.metadata.create_all)

    asyncio.run(setup())


@pytest.fixture(autouse=True)
async def _clean(monkeypatch) -> AsyncIterator[None]:
    tables = ", ".join(t.name for t in Base.metadata.sorted_tables)
    async with engine.begin() as c:
        await c.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE"))
    deps.verifier.cache_clear()
    monkeypatch.setattr(deps, "verifier", lambda: SsoVerifier(issuer="http://auth.test", audience="scolaris", jwks_fetch=lambda: JWKS))
    calls: dict = {"enrolled": [], "removed": [], "session_alive": True}

    async def enrol(*, phone, display_name, role):
        calls["enrolled"].append((phone, display_name, role))
        return uuid.uuid4()

    async def remove(uid):
        calls["removed"].append(uid)

    async def alive(sid):
        return calls["session_alive"]

    monkeypatch.setattr(auth_client, "enrol_staff", enrol)
    monkeypatch.setattr(auth_client, "remove_staff", remove)
    monkeypatch.setattr(auth_client, "session_active", alive)
    monkeypatch.setattr("app.routers.school.auth_client", auth_client)
    pytest.auth_calls = calls
    yield


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


async def make_school(name: str = "Ecole A") -> tuple[int, int]:
    async with SessionLocal() as db:
        s = School(name=name, city="Abidjan")
        db.add(s)
        await db.flush()
        from datetime import date

        y = AcademicYear(school_id=s.id, label="2026-2027", starts_on=date(2026, 9, 14), ends_on=date(2027, 6, 30), is_current=True)
        db.add(y)
        await db.commit()
        return s.id, y.id


async def make_staff(school_id: int, role: str, name: str = "Staff") -> dict:
    uid = uuid.uuid4()
    async with SessionLocal() as db:
        db.add(StaffMember(school_id=school_id, auth_user_id=uid, display_name=name, role=role))
        await db.commit()
    return {"Authorization": f"Bearer {make_token(uid, role)}"}, uid


@pytest.fixture
async def school() -> dict:
    sid, yid = await make_school()
    director, duid = await make_staff(sid, "director", "Directrice")
    accountant, _ = await make_staff(sid, "accountant", "Caissier")
    secretary, _ = await make_staff(sid, "secretary", "Secretaire")
    teacher, _ = await make_staff(sid, "teacher", "Prof Math")
    teacher2, _ = await make_staff(sid, "teacher", "Prof Francais")
    return {"id": sid, "year_id": yid, "director": director, "accountant": accountant, "secretary": secretary, "teacher": teacher, "teacher2": teacher2, "director_uid": duid}
