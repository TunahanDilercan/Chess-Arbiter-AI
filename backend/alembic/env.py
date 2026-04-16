"""
Alembic migration environment — async-aware for SQLAlchemy async engine.

This env.py supports both:
  - Online mode (real DB connection, used by `alembic upgrade head`)
  - Offline mode (SQL script generation, used by `alembic upgrade head --sql`)
"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

# ── Load app config and models ────────────────────────────────────────────────
# These imports ensure all models are registered with Base.metadata before
# Alembic inspects it for autogenerate.
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from config import settings
from models.base import Base
from models import game as _game_models  # noqa: F401 — registers all ORM models

# ── Alembic config ────────────────────────────────────────────────────────────

config = context.config

# Inject DATABASE_URL from app settings (overrides alembic.ini if set)
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


# ── Offline mode ──────────────────────────────────────────────────────────────


def run_migrations_offline() -> None:
    """Generate SQL statements without a live DB connection."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


# ── Online mode ───────────────────────────────────────────────────────────────


def do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """Run migrations using an async engine (asyncpg)."""
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


# ── Entry point ──��────────────────────────────────────────────────────────────

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
