"""
Security middleware: response headers + per-IP rate limiting.

Designed for an internet-facing deployment behind a TLS-terminating reverse
proxy (nginx/Caddy). TLS, request body size caps and CSP for the docs UI
belong at the proxy layer — see docs/DEPLOYMENT.md.

Rate limiting
─────────────
Fixed one-minute window per (client IP, scope). Counters live in Redis so
limits hold across multiple uvicorn workers; if Redis is unreachable the
middleware degrades to a per-process in-memory counter rather than failing
open completely or taking the API down.

Scopes:
  "upload"  — POST /api/upload (expensive: storage + Celery + OCR cost)
  "default" — everything else except /health and /api/sse
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import time
from typing import Dict, Optional, Tuple

from fastapi import FastAPI, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from config import settings

logger = logging.getLogger(__name__)


# ── Signed storage URLs ───────────────────────────────────────────────────────
# Stored files (uploaded scoresheets + move crops) can contain personal data
# (player names, signatures). They must not be world-readable via a static mount.
# Instead the API hands out short-lived HMAC-signed URLs and a guarded route
# (main.py) verifies the signature before serving the bytes.


def _storage_sig(key: str, exp: int) -> str:
    msg = f"{key}:{exp}".encode("utf-8")
    return hmac.new(
        settings.SECRET_KEY.encode("utf-8"), msg, hashlib.sha256
    ).hexdigest()


def sign_storage_key(key: str, ttl: Optional[int] = None) -> str:
    """Return a relative, expiring, signed URL for a storage key."""
    seconds = ttl if ttl is not None else settings.STORAGE_URL_TTL_SECONDS
    exp = int(time.time()) + seconds
    return f"/storage/{key}?exp={exp}&sig={_storage_sig(key, exp)}"


def verify_storage_sig(key: str, exp: int, sig: str) -> bool:
    """Validate a signed storage URL: correct HMAC and not expired."""
    if exp < int(time.time()):
        return False
    return hmac.compare_digest(_storage_sig(key, exp), sig or "")


# ── Security headers ──────────────────────────────────────────────────────────


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Attach standard security headers to every response."""

    async def dispatch(self, request: Request, call_next: object) -> Response:
        response: Response = await call_next(request)  # type: ignore[operator]
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault(
            "Permissions-Policy", "camera=(), microphone=(), geolocation=()"
        )
        if settings.ENABLE_HSTS:
            # Only meaningful when served over HTTPS (behind the proxy).
            response.headers.setdefault(
                "Strict-Transport-Security", "max-age=63072000; includeSubDomains"
            )
        return response


# ── Rate limiting ─────────────────────────────────────────────────────────────


def client_ip(request: Request) -> str:
    """
    Resolve the client IP.

    With TRUST_PROXY_HEADERS=true the first X-Forwarded-For entry wins —
    only enable this when the app is reachable exclusively through a proxy
    that overwrites the header, otherwise clients can spoof their IP.
    """
    if settings.TRUST_PROXY_HEADERS:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Fixed-window per-IP rate limiter (Redis-backed, in-memory fallback)."""

    WINDOW_SECONDS = 60

    def __init__(self, app: FastAPI) -> None:
        super().__init__(app)
        self._redis: Optional[object] = None
        self._redis_failed_at: float = 0.0
        # In-memory fallback: {key: (window_start_epoch, count)}
        self._local: Dict[str, Tuple[float, int]] = {}

    # ── Scope / limits ────────────────────────────────────────────────────────

    @staticmethod
    def _scope_for(request: Request) -> Optional[Tuple[str, int]]:
        """Return (scope_name, limit_per_minute) or None when exempt."""
        path = request.url.path
        if path == "/health" or path.startswith("/api/sse"):
            return None
        if request.method == "OPTIONS":  # CORS preflight
            return None
        if path.startswith("/api/upload"):
            return "upload", settings.RATE_LIMIT_UPLOADS_PER_MINUTE
        return "default", settings.RATE_LIMIT_PER_MINUTE

    # ── Counter backends ──────────────────────────────────────────────────────

    async def _get_redis(self) -> Optional[object]:
        """Lazily connect to Redis; back off for 30 s after a failure."""
        if self._redis is not None:
            return self._redis
        if time.monotonic() - self._redis_failed_at < 30.0:
            return None
        try:
            import redis.asyncio as aioredis

            self._redis = aioredis.from_url(
                settings.REDIS_URL, decode_responses=True, socket_timeout=1.0,
                socket_connect_timeout=1.0,
            )
            return self._redis
        except Exception as exc:  # noqa: BLE001
            self._redis_failed_at = time.monotonic()
            logger.warning("Rate limiter: Redis unavailable (%s) — using in-memory counters.", exc)
            return None

    async def _increment(self, key: str) -> int:
        """Increment the window counter for *key* and return the new count."""
        redis = await self._get_redis()
        if redis is not None:
            try:
                count = await redis.incr(key)  # type: ignore[attr-defined]
                if count == 1:
                    await redis.expire(key, self.WINDOW_SECONDS)  # type: ignore[attr-defined]
                return int(count)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Rate limiter: Redis error (%s) — falling back to memory.", exc)
                self._redis = None
                self._redis_failed_at = time.monotonic()

        # In-memory fallback (per-process).
        now = time.time()
        window_start, count = self._local.get(key, (now, 0))
        if now - window_start >= self.WINDOW_SECONDS:
            window_start, count = now, 0
        count += 1
        self._local[key] = (window_start, count)
        if len(self._local) > 10_000:  # bound memory under IP churn
            cutoff = now - self.WINDOW_SECONDS
            self._local = {
                k: v for k, v in self._local.items() if v[0] >= cutoff
            }
        return count

    # ── Dispatch ──────────────────────────────────────────────────────────────

    async def dispatch(self, request: Request, call_next: object) -> Response:
        if not settings.RATE_LIMIT_ENABLED:
            return await call_next(request)  # type: ignore[operator]

        scoped = self._scope_for(request)
        if scoped is None:
            return await call_next(request)  # type: ignore[operator]

        scope, limit = scoped
        window = int(time.time() // self.WINDOW_SECONDS)
        key = f"ratelimit:{scope}:{client_ip(request)}:{window}"
        count = await self._increment(key)

        if count > limit:
            logger.warning(
                "Rate limit exceeded — ip=%s scope=%s count=%d limit=%d",
                client_ip(request), scope, count, limit,
            )
            return Response(
                content='{"detail":"Too many requests. Please slow down."}',
                status_code=429,
                media_type="application/json",
                headers={"Retry-After": str(self.WINDOW_SECONDS)},
            )

        return await call_next(request)  # type: ignore[operator]


# ── Startup configuration audit ───────────────────────────────────────────────


def warn_insecure_config() -> None:
    """Log loud warnings for insecure production configurations."""
    if settings.DEBUG:
        return  # dev mode — anything goes
    if settings.CORS_ORIGINS == ["*"]:
        logger.warning(
            "SECURITY: CORS_ORIGINS is '*' with DEBUG=false. Set explicit "
            "origins (e.g. https://app.example.com) for production."
        )
    if not settings.RATE_LIMIT_ENABLED:
        logger.warning("SECURITY: rate limiting is DISABLED with DEBUG=false.")
    if "arbiter:arbiter@" in settings.DATABASE_URL:
        logger.warning(
            "SECURITY: DATABASE_URL uses the default dev credentials. "
            "Change the PostgreSQL password for production."
        )
    if settings.SECRET_KEY == "dev-insecure-change-me":
        logger.warning(
            "SECURITY: SECRET_KEY is the default value with DEBUG=false. "
            "Set a strong random SECRET_KEY — signed storage URLs are forgeable "
            "without it."
        )
