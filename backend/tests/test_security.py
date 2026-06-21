"""
Tests for security middleware (security.py) and upload content validation.
"""

from __future__ import annotations

import io
from unittest.mock import patch

import pytest
from PIL import Image


def _png_bytes() -> bytes:
    buf = io.BytesIO()
    Image.new("L", (32, 32), color=255).save(buf, format="PNG")
    return buf.getvalue()


# ── Security headers ──────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_security_headers_present(app_client):
    resp = await app_client.get("/health")
    assert resp.headers["x-content-type-options"] == "nosniff"
    assert resp.headers["x-frame-options"] == "DENY"
    assert resp.headers["referrer-policy"] == "no-referrer"
    assert "permissions-policy" in resp.headers


@pytest.mark.asyncio
async def test_hsts_absent_by_default(app_client):
    resp = await app_client.get("/health")
    assert "strict-transport-security" not in resp.headers


# ── Rate limiting ─────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_rate_limit_returns_429_when_exceeded(app_client):
    import security as security_module

    with patch.object(security_module.settings, "RATE_LIMIT_ENABLED", True), \
         patch.object(security_module.settings, "RATE_LIMIT_PER_MINUTE", 3):
        # Force the in-memory backend so the test never touches Redis.
        with patch.object(
            security_module.RateLimitMiddleware, "_get_redis", return_value=None
        ):
            statuses = []
            for _ in range(5):
                resp = await app_client.get("/api/games/?session_id=rl-test")
                statuses.append(resp.status_code)

    assert 429 in statuses
    assert statuses[0] != 429  # first request always passes


@pytest.mark.asyncio
async def test_health_exempt_from_rate_limit(app_client):
    import security as security_module

    with patch.object(security_module.settings, "RATE_LIMIT_ENABLED", True), \
         patch.object(security_module.settings, "RATE_LIMIT_PER_MINUTE", 1):
        with patch.object(
            security_module.RateLimitMiddleware, "_get_redis", return_value=None
        ):
            for _ in range(5):
                resp = await app_client.get("/health")
                assert resp.status_code == 200


# ── Upload content validation ─────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_upload_rejects_content_mismatching_declared_type(app_client):
    """A text payload declared as image/jpeg must be rejected by magic bytes."""
    resp = await app_client.post(
        "/api/upload/",
        files={"file": ("evil.jpg", io.BytesIO(b"<script>alert(1)</script>"), "image/jpeg")},
    )
    assert resp.status_code == 400
    assert "does not match" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_upload_accepts_real_png_with_wrong_extension(app_client):
    """Magic bytes are authoritative — a real PNG named .jpg is fine."""
    resp = await app_client.post(
        "/api/upload/",
        files={"file": ("scan.jpg", io.BytesIO(_png_bytes()), "image/jpeg")},
    )
    assert resp.status_code == 201


@pytest.mark.asyncio
async def test_upload_rejects_invalid_session_id(app_client):
    resp = await app_client.post(
        "/api/upload/",
        files={"file": ("scan.png", io.BytesIO(_png_bytes()), "image/png")},
        data={"session_id": "<img src=x onerror=alert(1)>"},
    )
    assert resp.status_code == 400
    assert "session_id" in resp.json()["detail"]


@pytest.mark.asyncio
async def test_upload_rejects_unknown_locale(app_client):
    resp = await app_client.post(
        "/api/upload/",
        files={"file": ("scan.png", io.BytesIO(_png_bytes()), "image/png")},
        data={"locale": "xx"},
    )
    assert resp.status_code == 400
    assert "locale" in resp.json()["detail"]


# ── Turkish notation mapping (regression for swapped V/F) ────────────────────


def test_turkish_locale_map_is_tsf_standard():
    """V=Vezir→Q and F=Fil→B; a swap here corrupts every Turkish scoresheet."""
    from services.chess.normalizer import LOCALE_PIECE_MAPS

    tr = LOCALE_PIECE_MAPS["tr"]
    assert tr["V"] == "Q"
    assert tr["F"] == "B"
    assert tr["Ş"] == "K"
    assert tr["K"] == "R"
    assert tr["A"] == "N"


# ── Signed storage URLs ────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_signed_storage_serves_file(app_client, tmp_path, monkeypatch):
    """A correctly signed, unexpired URL serves the stored bytes."""
    from services import storage as storage_module
    from services.storage import LocalStorageBackend
    from security import sign_storage_key

    backend = LocalStorageBackend(str(tmp_path))
    monkeypatch.setattr(storage_module, "_storage_instance", backend)
    await backend.save(b"hello-bytes", "crops/g1/0.png", "image/png")

    resp = await app_client.get(sign_storage_key("crops/g1/0.png"))
    assert resp.status_code == 200
    assert resp.content == b"hello-bytes"


@pytest.mark.asyncio
async def test_unsigned_storage_returns_404(app_client):
    """Without a signature the file is not served (no public static access)."""
    resp = await app_client.get("/storage/crops/g1/0.png")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_tampered_storage_sig_returns_404(app_client):
    from security import sign_storage_key

    resp = await app_client.get(sign_storage_key("crops/g1/0.png") + "tampered")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_expired_storage_url_returns_404(app_client):
    from security import _storage_sig

    exp = 1  # 1970 — long expired
    sig = _storage_sig("crops/g1/0.png", exp)
    resp = await app_client.get(f"/storage/crops/g1/0.png?exp={exp}&sig={sig}")
    assert resp.status_code == 404
