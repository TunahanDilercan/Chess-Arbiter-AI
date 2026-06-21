"""
Arbiter AI — FastAPI application entry point.

Run locally:
    uvicorn main:app --reload

Interactive docs:
    http://localhost:8000/docs   (Swagger UI)
    http://localhost:8000/redoc  (ReDoc)
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncGenerator

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware

from api.routes import games, review, sse, upload
from config import settings
from logging_config import setup_logging
from security import (
    RateLimitMiddleware,
    SecurityHeadersMiddleware,
    warn_insecure_config,
)

# Initialise structured logging before any other module emits a log line.
setup_logging(debug=settings.DEBUG)

logger = logging.getLogger(__name__)


# ── Timeout middleware ────────────────────────────────────────────────────────


class TimeoutMiddleware(BaseHTTPMiddleware):
    """Return HTTP 504 if a request handler takes longer than *timeout* seconds.

    SSE endpoints (``/api/sse/*``) are exempt: they stream indefinitely and
    must not be cut off by a global request deadline.
    """

    def __init__(self, app: FastAPI, timeout: int = 30) -> None:
        super().__init__(app)
        self.timeout = timeout

    async def dispatch(self, request: Request, call_next: object) -> Response:
        # Let SSE streams run indefinitely.
        if request.url.path.startswith("/api/sse"):
            return await call_next(request)  # type: ignore[operator]
        try:
            return await asyncio.wait_for(
                call_next(request),  # type: ignore[arg-type]
                timeout=self.timeout,
            )
        except asyncio.TimeoutError:
            logger.warning(
                "Request timed out",
                extra={"path": request.url.path, "timeout": self.timeout},
            )
            return Response(
                content='{"detail":"Request timed out"}',
                status_code=504,
                media_type="application/json",
            )


# ── Lifespan ──────────────────────────────────────────────────────────────────


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """
    Startup / shutdown logic.

    Startup:
      - Create storage directory
      - Optionally create DB tables (dev mode; production uses Alembic)

    Shutdown:
      - Dispose SQLAlchemy engine connection pool
    """
    # ── Startup ───────────────────────────────────────────────────────────────
    logger.info("Starting Arbiter AI v%s", settings.APP_VERSION)
    warn_insecure_config()

    # Ensure local storage directory exists
    Path(settings.LOCAL_STORAGE_PATH).mkdir(parents=True, exist_ok=True)

    if settings.AUTO_CREATE_TABLES:
        from database import create_tables
        try:
            await create_tables()
            logger.info("Database tables verified/created.")
        except Exception as exc:
            # Non-fatal in dev: log and continue. In production AUTO_CREATE_TABLES=False.
            logger.warning("Could not create tables (DB may not be running): %s", exc)

    yield  # application runs here

    # ── Shutdown ──────────────────────────────────────────────────────────────
    from database import engine
    await engine.dispose()
    logger.info("Database engine disposed. Shutdown complete.")


# ── App factory ───────────────────────────────────────────────────────────────


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.APP_TITLE,
        description=(
            "Chess scoresheet OCR and FIDE analysis backend.\n\n"
            "**Phase 1**: Chess engine core + FIDE analysis (stateless endpoint).\n"
            "**Phase 2**: File upload + PostgreSQL persistence.\n"
            "Upload a scoresheet → get back a fully annotated game with FIDE findings."
        ),
        version=settings.APP_VERSION,
        # Interactive API docs expose the full schema; keep them off in
        # production (DEBUG=false) to reduce the attack surface.
        docs_url="/docs" if settings.DEBUG else None,
        redoc_url="/redoc" if settings.DEBUG else None,
        openapi_url="/openapi.json" if settings.DEBUG else None,
        lifespan=lifespan,
    )

    # Middlewares are applied in reverse registration order (last in = outermost).
    app.add_middleware(TimeoutMiddleware, timeout=30)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        # No cookie/credential auth is used (anonymous sessions live in a
        # client-supplied header/param), so credentials stay off. This also
        # avoids the invalid "* origin + credentials" combination.
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(RateLimitMiddleware)
    app.add_middleware(SecurityHeadersMiddleware)

    # ── Phase 1: Chess analysis ────────────────────────────────────────────
    app.include_router(games.router, prefix="/api/games", tags=["games"])

    # ── Phase 2: Upload ────────────────────────────────────────────────────
    app.include_router(upload.router, prefix="/api/upload", tags=["upload"])

    # Serve uploaded/cropped files at /storage/* (local dev only)
    # In production, files are served directly from S3/CDN.
    storage_path = Path(settings.LOCAL_STORAGE_PATH)
    storage_path.mkdir(parents=True, exist_ok=True)
    app.mount("/storage", StaticFiles(directory=str(storage_path)), name="storage")

    # ── Phase 7: SSE job status streaming ─────────────────────────────────
    app.include_router(sse.router, prefix="/api/sse", tags=["sse"])

    # ── Phase 6: Review / manual correction ───────────────────────────────
    app.include_router(review.router, prefix="/api/games", tags=["review"])

    return app


app = create_app()


@app.get("/health", tags=["health"], summary="Health check")
async def health_check() -> dict:
    return {"status": "ok", "version": settings.APP_VERSION}
