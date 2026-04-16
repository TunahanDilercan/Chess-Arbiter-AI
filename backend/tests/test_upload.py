"""
Tests for POST /api/upload and GET /api/games/{game_id}.

All tests use the in-memory SQLite DB via the app_client fixture.
No real PostgreSQL or file system (except tmp_storage for storage unit tests).

Run: pytest tests/test_upload.py -v
"""

from __future__ import annotations

import io
from pathlib import Path

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from services.storage import LocalStorageBackend


# ── Upload endpoint ───────────────────────────────────────────────────────────


async def test_upload_jpeg_returns_201(
    app_client: AsyncClient, sample_jpeg_bytes: bytes, tmp_storage: Path, monkeypatch
) -> None:
    """A valid JPEG upload should return 201 with game_id, job_id, and URLs."""
    # Point storage at tmp dir so files land somewhere real
    from services import storage as storage_module
    monkeypatch.setattr(
        storage_module, "_storage_instance", LocalStorageBackend(str(tmp_storage))
    )

    response = await app_client.post(
        "/api/upload/",
        files={"file": ("scoresheet.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
        data={"session_id": "test-session-001", "locale": "en"},
    )

    assert response.status_code == 201
    body = response.json()
    assert "game_id" in body
    assert "job_id" in body
    assert body["status"] == "queued"
    assert body["sse_url"].startswith("/api/sse/")
    assert body["game_url"].startswith("/api/games/")


async def test_upload_png_accepted(
    app_client: AsyncClient, sample_png_bytes: bytes, tmp_storage: Path, monkeypatch
) -> None:
    from services import storage as storage_module
    monkeypatch.setattr(
        storage_module, "_storage_instance", LocalStorageBackend(str(tmp_storage))
    )

    response = await app_client.post(
        "/api/upload/",
        files={"file": ("scan.png", io.BytesIO(sample_png_bytes), "image/png")},
        data={"session_id": "test-session-002"},
    )
    assert response.status_code == 201


async def test_upload_invalid_mime_returns_400(
    app_client: AsyncClient,
) -> None:
    """A .txt file should be rejected with 400."""
    response = await app_client.post(
        "/api/upload/",
        files={"file": ("moves.txt", io.BytesIO(b"e4 e5 Nf3"), "text/plain")},
    )
    assert response.status_code == 400
    assert "Unsupported file type" in response.json()["detail"]


async def test_upload_empty_file_returns_400(
    app_client: AsyncClient,
) -> None:
    response = await app_client.post(
        "/api/upload/",
        files={"file": ("empty.jpg", io.BytesIO(b""), "image/jpeg")},
    )
    assert response.status_code == 400
    assert "empty" in response.json()["detail"].lower()


async def test_upload_too_large_returns_400(
    app_client: AsyncClient, monkeypatch
) -> None:
    """Files larger than MAX_UPLOAD_SIZE_MB should be rejected."""
    from config import settings as cfg
    monkeypatch.setattr(cfg, "MAX_UPLOAD_SIZE_MB", 1)  # 1 MB limit for this test

    big_data = b"\xFF\xD8\xFF" + b"x" * (2 * 1024 * 1024)  # 2 MB fake JPEG
    response = await app_client.post(
        "/api/upload/",
        files={"file": ("big.jpg", io.BytesIO(big_data), "image/jpeg")},
    )
    assert response.status_code == 400
    assert "too large" in response.json()["detail"].lower()


async def test_upload_session_id_auto_generated(
    app_client: AsyncClient, sample_jpeg_bytes: bytes, tmp_storage: Path, monkeypatch
) -> None:
    """If no session_id is provided, one should be generated."""
    from services import storage as storage_module
    monkeypatch.setattr(
        storage_module, "_storage_instance", LocalStorageBackend(str(tmp_storage))
    )

    response = await app_client.post(
        "/api/upload/",
        files={"file": ("scan.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
        # No session_id provided
    )
    assert response.status_code == 201
    game_id = response.json()["game_id"]

    # Verify the game was created by fetching it
    get_response = await app_client.get(f"/api/games/{game_id}")
    assert get_response.status_code == 200
    assert get_response.json()["session_id"]  # non-empty, auto-generated


# ── GET /api/games/{game_id} ───────────────────────────────────────��──────────


async def test_get_game_after_upload(
    app_client: AsyncClient, sample_jpeg_bytes: bytes, tmp_storage: Path, monkeypatch
) -> None:
    """After upload, GET should return the game with status=processing."""
    from services import storage as storage_module
    monkeypatch.setattr(
        storage_module, "_storage_instance", LocalStorageBackend(str(tmp_storage))
    )

    upload_resp = await app_client.post(
        "/api/upload/",
        files={"file": ("test.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
        data={"session_id": "test-session-get"},
    )
    assert upload_resp.status_code == 201
    game_id = upload_resp.json()["game_id"]

    get_resp = await app_client.get(f"/api/games/{game_id}")
    assert get_resp.status_code == 200
    body = get_resp.json()

    assert body["game_id"] == game_id
    assert body["session_id"] == "test-session-get"
    assert body["status"] in ("processing", "queued")
    assert body["moves"] == []           # not processed yet
    assert body["findings"] == []        # not processed yet
    assert body["upload_metadata"]["filename"] == "test.jpg"


async def test_get_game_not_found_returns_404(app_client: AsyncClient) -> None:
    response = await app_client.get("/api/games/00000000-0000-0000-0000-000000000000")
    assert response.status_code == 404
    assert "not found" in response.json()["detail"].lower()


# ── GET /api/games/ (list) ────────────────────────────────────────────────────


async def test_list_games_for_session(
    app_client: AsyncClient, sample_jpeg_bytes: bytes, tmp_storage: Path, monkeypatch
) -> None:
    """Uploading 2 files under the same session should return 2 summaries."""
    from services import storage as storage_module
    monkeypatch.setattr(
        storage_module, "_storage_instance", LocalStorageBackend(str(tmp_storage))
    )

    session = "session-list-test"
    for i in range(2):
        resp = await app_client.post(
            "/api/upload/",
            files={"file": (f"scan{i}.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
            data={"session_id": session},
        )
        assert resp.status_code == 201

    list_resp = await app_client.get(f"/api/games/?session_id={session}")
    assert list_resp.status_code == 200
    games = list_resp.json()
    assert len(games) == 2
    assert all(g["session_id"] == session for g in games)


async def test_list_games_empty_session(app_client: AsyncClient) -> None:
    response = await app_client.get("/api/games/?session_id=nonexistent-session")
    assert response.status_code == 200
    assert response.json() == []


# ── Storage service unit tests ────────────────────────────────────────────────


async def test_local_storage_save_and_get_url(tmp_storage: Path) -> None:
    backend = LocalStorageBackend(str(tmp_storage))
    data = b"fake image bytes"
    key = "uploads/game-123/image.jpg"

    await backend.save(data, key, "image/jpeg")

    # File should exist on disk
    stored = tmp_storage / key
    assert stored.exists()
    assert stored.read_bytes() == data

    url = await backend.get_url(key)
    assert url == f"/storage/{key}"


async def test_local_storage_delete(tmp_storage: Path) -> None:
    backend = LocalStorageBackend(str(tmp_storage))
    key = "uploads/game-del/file.jpg"

    await backend.save(b"data", key, "image/jpeg")
    assert (tmp_storage / key).exists()

    await backend.delete(key)
    assert not (tmp_storage / key).exists()


async def test_local_storage_delete_nonexistent_is_noop(tmp_storage: Path) -> None:
    """Deleting a non-existent key must not raise."""
    backend = LocalStorageBackend(str(tmp_storage))
    await backend.delete("uploads/does-not-exist/file.jpg")  # should not raise


async def test_local_storage_nested_dirs_created(tmp_storage: Path) -> None:
    backend = LocalStorageBackend(str(tmp_storage))
    key = "crops/game-abc/move-05/crop.png"
    await backend.save(b"pixels", key, "image/png")
    assert (tmp_storage / key).exists()


# ── Job service unit tests ────────────────────────────────────────────────────


async def test_create_game_with_upload(async_session: AsyncSession) -> None:
    from services.job_service import create_game_with_upload
    from models.game import Game, UploadedAsset, ProcessingJob

    game, asset, job = await create_game_with_upload(
        async_session,
        session_id="unit-test-session",
        locale="tr",
        file_path="uploads/test-game/scan.jpg",
        file_type="image/jpeg",
        original_filename="scan.jpg",
        file_size_bytes=12345,
    )
    await async_session.commit()

    assert game.id
    assert game.session_id == "unit-test-session"
    assert game.locale == "tr"
    assert asset.game_id == game.id
    assert asset.file_size_bytes == 12345
    assert job.game_id == game.id
    assert job.status == "queued"


async def test_update_job_status(async_session: AsyncSession) -> None:
    from services.job_service import create_game_with_upload, update_job_status

    _, _, job = await create_game_with_upload(
        async_session,
        session_id="status-test",
        locale="en",
        file_path="uploads/x/y.jpg",
        file_type="image/jpeg",
        original_filename="y.jpg",
        file_size_bytes=100,
    )
    await async_session.commit()

    updated = await update_job_status(async_session, job.id, "completed")
    await async_session.commit()

    assert updated is not None
    assert updated.status == "completed"
    assert updated.completed_at is not None


async def test_get_game_full_with_upload(async_session: AsyncSession) -> None:
    from services.job_service import create_game_with_upload, get_game_full

    game, _, _ = await create_game_with_upload(
        async_session,
        session_id="full-test",
        locale="en",
        file_path="uploads/g/f.jpg",
        file_type="image/jpeg",
        original_filename="f.jpg",
        file_size_bytes=500,
    )
    await async_session.commit()

    fetched = await get_game_full(async_session, game.id)
    assert fetched is not None
    assert fetched.id == game.id
    assert fetched.uploaded_asset is not None
    assert fetched.processing_job is not None
    assert fetched.move_entries == []

    none_result = await get_game_full(async_session, "nonexistent-id")
    assert none_result is None
