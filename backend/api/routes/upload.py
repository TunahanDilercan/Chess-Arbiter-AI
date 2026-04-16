"""
POST /api/upload — scoresheet file upload endpoint.

Flow:
  1. Validate file (MIME type, size)
  2. Save to storage backend
  3. Create Game + UploadedAsset + ProcessingJob records
  4. Commit DB so the Celery worker can read the records immediately
  5. Dispatch process_scoresheet_task to the Celery worker queue
  6. Return {game_id, job_id, sse_url, game_url} immediately
"""

from __future__ import annotations

import logging
import mimetypes
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from config import settings
from database import get_db
from schemas.upload import UploadResponse
from services.job_service import create_game_with_upload
from services.storage import StorageBackend, get_storage_cached
from workers.processing_tasks import process_scoresheet_task

logger = logging.getLogger(__name__)

router = APIRouter()

# ── Allowed types ─────────────────────────────────────────────────────────────

ALLOWED_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/tiff",
    "application/pdf",
}

# MIME types whose content can be processed by OpenCV directly (Phase 3+)
# PDFs need server-side conversion to image first
IMAGE_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/tiff",
}


def _detect_mime(file: UploadFile) -> str:
    """
    Determine MIME type: prefer the declared content_type, fall back to
    sniffing by filename extension.  Never trust the client blindly — the
    declared type is validated against ALLOWED_MIME_TYPES after this.
    """
    ct = file.content_type or ""
    if ct and ct in ALLOWED_MIME_TYPES:
        return ct
    # Fallback: guess from filename
    if file.filename:
        guessed, _ = mimetypes.guess_type(file.filename)
        if guessed and guessed in ALLOWED_MIME_TYPES:
            return guessed
    return ct  # return as-is; validation will reject if not allowed


def _storage_key(game_id: str, filename: str) -> str:
    """
    Build a storage key for an uploaded file.
    Format: uploads/{game_id}/{sanitized_filename}
    Sanitization replaces any path separators to prevent directory traversal.
    """
    safe_name = filename.replace("/", "_").replace("\\", "_").replace("..", "_")
    return f"uploads/{game_id}/{safe_name}"


# ── Endpoint ──────────────────────────────────────────────────────────────────


@router.post(
    "/",
    response_model=UploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a scoresheet",
    description=(
        "Upload a handwritten chess scoresheet image or PDF.\n\n"
        "Accepted formats: JPEG, PNG, WebP, TIFF, PDF (max "
        f"{settings.MAX_UPLOAD_SIZE_MB} MB).\n\n"
        "Returns immediately with `game_id` and `job_id`. "
        "Connect to `sse_url` for real-time processing updates (Phase 7+), "
        "or poll `game_url` until `status` is `completed`."
    ),
    responses={
        201: {"description": "Upload accepted, job queued."},
        400: {"description": "Invalid file type or file too large."},
        500: {"description": "Storage or database error."},
    },
)
async def upload_scoresheet(
    file: UploadFile,
    session_id: Optional[str] = Form(default=None),
    locale: str = Form(default="en"),
    db: AsyncSession = Depends(get_db),
    storage: StorageBackend = Depends(get_storage_cached),
) -> UploadResponse:
    """
    Upload endpoint.

    Args:
        file:       Multipart file field (required)
        session_id: Anonymous session UUID; auto-generated if omitted
        locale:     Piece notation locale for analysis (en/tr/de/fr/es)
    """
    # ── Validate MIME type ────────────────────────────────────────────────────
    mime_type = _detect_mime(file)
    if mime_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Unsupported file type '{mime_type}'. "
                f"Accepted: {', '.join(sorted(ALLOWED_MIME_TYPES))}."
            ),
        )

    # ── Read and validate size ─────────────────────────────────────────────────
    max_bytes = settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024
    data = await file.read()

    if len(data) == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Uploaded file is empty.",
        )

    if len(data) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"File too large: {len(data) / 1024 / 1024:.1f} MB. "
                f"Maximum allowed: {settings.MAX_UPLOAD_SIZE_MB} MB."
            ),
        )

    # ── Resolve session ────────────────────────────────────────────────────────
    resolved_session_id = session_id or str(uuid.uuid4())

    # ── Generate game ID early so we can use it in the storage key ────────────
    game_id = str(uuid.uuid4())
    original_filename = file.filename or f"upload_{game_id}"
    storage_key = _storage_key(game_id, original_filename)

    # ── Save to storage ────────────────────────────────────────────────────────
    try:
        await storage.save(data, storage_key, mime_type)
    except Exception as exc:
        logger.exception("Storage error for game %s", game_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to store uploaded file.",
        ) from exc

    # ── Persist DB records ─────────────────────────────────────────────────────
    try:
        game, _, job = await create_game_with_upload(
            db,
            session_id=resolved_session_id,
            locale=locale,
            file_path=storage_key,
            file_type=mime_type,
            original_filename=original_filename,
            file_size_bytes=len(data),
        )
    except Exception as exc:
        logger.exception("DB error creating game records")
        # Best-effort cleanup of stored file
        try:
            await storage.delete(storage_key)
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create game record.",
        ) from exc

    # ── Commit before dispatch ─────────────────────────────────────────────────
    # The Celery worker runs in a separate process and reads the DB via its own
    # connection.  We must commit here so the Game/Job/Asset rows are visible
    # before the worker starts — otherwise the worker races the transaction and
    # may find nothing.  get_db() will commit again after we return (no-op since
    # no new writes happen between here and the return statement, unless we set
    # celery_task_id below).
    await db.commit()

    # ── Dispatch Celery task ───────────────────────────────────────────────────
    try:
        celery_result = process_scoresheet_task.apply_async(
            kwargs={"job_id": job.id, "game_id": game.id},
        )
    except Exception as exc:
        # Broker is unreachable — the file was saved and the job record exists,
        # but nothing will process it.  Fail fast so the client can retry rather
        # than waiting forever on a job that will never run.
        logger.exception(
            "Celery dispatch failed for job=%s game=%s", job.id, game.id
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to queue processing job. Please try again.",
        ) from exc

    # Persist the Celery task ID so the job can be tracked / cancelled later.
    # get_db() will commit this after the route returns.
    job.celery_task_id = celery_result.id

    logger.info(
        "Upload accepted and task dispatched: game=%s job=%s celery_task=%s "
        "session=%s size=%dB type=%s",
        game.id,
        job.id,
        celery_result.id,
        resolved_session_id,
        len(data),
        mime_type,
    )

    return UploadResponse(
        game_id=game.id,
        job_id=job.id,
        status="queued",
        sse_url=f"/api/sse/{job.id}",
        game_url=f"/api/games/{game.id}",
    )
