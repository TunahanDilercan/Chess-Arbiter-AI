"""
Shared test fixtures for Phase 2+ tests.

Key fixtures:
  async_session   — AsyncSession backed by in-memory SQLite (no real Postgres needed)
  app_client      — httpx AsyncClient wired to the FastAPI app with DB override
  tmp_storage     — temporary directory for storage tests

SQLite is used instead of PostgreSQL so the test suite runs anywhere without
a running database.  The SQLAlchemy dialect differences are small enough that
all Phase 2 logic is correctly exercised.
"""

from __future__ import annotations

import io
from pathlib import Path
from typing import AsyncGenerator
from unittest.mock import MagicMock, patch

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from database import get_db
from main import app
from models.base import Base


# ── Celery task mock ──────────────────────────────────────────────────────────
# Redis / a running broker is not available in the test environment.
# Patch process_scoresheet_task.apply_async so upload tests don't fail
# trying to connect to a broker that doesn't exist.


@pytest.fixture(autouse=True)
def mock_celery_task():
    """
    Globally suppress real Celery task dispatch for all tests.

    Replaces api.routes.upload.process_scoresheet_task with a mock whose
    apply_async() returns a fake AsyncResult with a fixed id.  Tests that
    want to assert on dispatch behaviour can inspect the yielded mock.
    """
    mock_result = MagicMock()
    mock_result.id = "test-celery-task-00000000-0000-0000-0000-000000000000"
    with patch("api.routes.upload.process_scoresheet_task") as mock_task:
        mock_task.apply_async.return_value = mock_result
        yield mock_task


# ── In-memory SQLite engine ────────────────────────────────────────────────────

TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"


@pytest_asyncio.fixture
async def async_engine():
    """Create a fresh in-memory SQLite engine per test."""
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def async_session(async_engine) -> AsyncGenerator[AsyncSession, None]:
    """Yield an AsyncSession connected to the in-memory SQLite DB."""
    session_factory = async_sessionmaker(
        async_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        yield session
        await session.rollback()  # clean up any uncommitted state


# ── FastAPI test client with DB override ──────────────────────────────────────


@pytest_asyncio.fixture
async def app_client(async_engine) -> AsyncGenerator[AsyncClient, None]:
    """
    httpx AsyncClient pointing at the FastAPI app.

    The real `get_db` dependency is overridden so every request uses
    the in-memory SQLite session instead of the Postgres engine.
    """
    session_factory = async_sessionmaker(
        async_engine, class_=AsyncSession, expire_on_commit=False
    )

    async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
        async with session_factory() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        yield client

    app.dependency_overrides.clear()


# ── Temporary storage ─────────────────────────────────────────────────────────


@pytest.fixture
def tmp_storage(tmp_path: Path) -> Path:
    """Return a temporary directory for storage tests."""
    storage = tmp_path / "storage"
    storage.mkdir()
    return storage


# ── Sample file fixtures ──────────────────────────────────────────────────────


@pytest.fixture
def sample_jpeg_bytes() -> bytes:
    """Minimal valid JPEG bytes (1x1 white pixel)."""
    # JPEG magic bytes + minimal valid structure
    return bytes([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
        0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
        0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
        0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
        0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
        0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
        0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
        0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
        0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
        0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
        0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0xFB, 0xD2,
        0x8A, 0x00, 0xFF, 0xD9,
    ])


@pytest.fixture
def sample_png_bytes() -> bytes:
    """Minimal valid PNG bytes (1x1 red pixel)."""
    import struct
    import zlib

    def chunk(name: bytes, data: bytes) -> bytes:
        c = name + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    raw = b"\x00\xFF\x00\x00"  # filter byte + RGB
    idat = chunk(b"IDAT", zlib.compress(raw))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend
