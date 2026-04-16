"""
Async SQLAlchemy engine and session factory.

Usage in route handlers:
    async def my_route(db: AsyncSession = Depends(get_db)):
        result = await db.execute(select(Game).where(Game.id == game_id))
        game = result.scalar_one_or_none()

Usage for startup table creation (dev only):
    await create_tables()

For production, run Alembic migrations instead of create_tables().
"""

from __future__ import annotations

from typing import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from config import settings
from models.base import Base  # noqa: F401 — imported so Base.metadata knows all tables

# ── Engine ────────────────────────────────────────────────────────────────────

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.DEBUG,
    # Pool settings for async Postgres — ignored by SQLite
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

# ── Session factory ───────────────────────────────────────────────────────────
# expire_on_commit=False is essential for async: prevents lazy-loading after commit

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


# ── FastAPI dependency ────────────────────────────────────────────────────────


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """
    Yields an AsyncSession for the duration of a request.
    Commits on success, rolls back on any exception.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


# ── Dev helper ────────────────────────────────────────────────────────────────


async def create_tables() -> None:
    """
    Create all tables via SQLAlchemy metadata.
    Only for development — in production use Alembic migrations.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def drop_tables() -> None:
    """Drop all tables. Used in tests only."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
