from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import NullPool

from app.config import get_settings


class Base(DeclarativeBase):
    pass


_s = get_settings()
# Tests run each case in its own event loop: pooled asyncpg connections cannot cross loops.
engine = (
    create_async_engine(_s.database_url, poolclass=NullPool)
    if _s.env == "test"
    else create_async_engine(_s.database_url, pool_pre_ping=True, pool_size=5, max_overflow=5)
)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
