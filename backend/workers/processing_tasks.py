"""
Celery task: process_scoresheet_task

Full processing pipeline for one uploaded scoresheet.

Status flow (success path)
──────────────────────────
    queued → preprocessing → cropping → ocr_processing → ocr_complete
                           ↘ failed                   ↘ failed

Status flow (any unhandled error)
──────────────────────────────────
    * → failed  (with error_message set)

Event loop / SQLAlchemy note
─────────────────────────────
Each Celery task invocation runs in a plain synchronous worker process.
We use asyncio.run() to execute async DB calls, which creates a new event
loop per invocation.  To avoid "connection already attached to a different
loop" errors we create a fresh SQLAlchemy engine with NullPool (no
connection pooling) for every task execution.  This is intentionally
different from the FastAPI engine which uses the default async pool.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, List, Optional, Tuple

from celery.signals import task_failure
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool

from config import settings
from services.cv.crop_extractor import CropExtractor, CropResult
from services.cv.grid_detector import GridDetectionError, GridDetector
from services.cv.preprocessor import ImagePreprocessor
from services.job_service import update_job_status
from services.ocr.base import OCRPrediction, OCRProvider
from services.storage import get_storage_cached
from workers.celery_app import celery_app

logger = logging.getLogger(__name__)


# ── Session factory ───────────────────────────────────────────────────────────

def _make_session() -> AsyncSession:
    """
    Create a one-shot async engine + session with NullPool.

    NullPool ensures no connections survive between asyncio.run() calls
    (each creates a new event loop, so connection reuse would error).
    """
    engine = create_async_engine(
        settings.DATABASE_URL,
        echo=False,
        poolclass=NullPool,
    )
    factory = sessionmaker(  # type: ignore[call-overload]
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    return factory()


async def _publish_status(
    job_id: str,
    status: str,
    error_message: Optional[str] = None,
) -> None:
    """
    Publish a status-change event to the Redis pub/sub channel
    ``job:{job_id}:status`` so SSE clients receive real-time updates.

    This is best-effort: any Redis error is logged but never raises, so
    pipeline failures are never caused by a missing/unavailable Redis.
    """
    try:
        import redis.asyncio as aioredis  # lazy import — not needed at module load

        channel = f"job:{job_id}:status"
        payload = json.dumps({"job_id": job_id, "status": status, "error_message": error_message})
        client = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        try:
            await client.publish(channel, payload)
            logger.debug("Published status %r to %s", status, channel)
        finally:
            await client.aclose()
    except Exception as exc:  # noqa: BLE001
        logger.warning("Could not publish SSE status (job_id=%s status=%r): %s", job_id, status, exc)


async def _set_status(
    session: AsyncSession,
    job_id: str,
    status: str,
    error_message: Optional[str] = None,
) -> None:
    """Update job status in DB, commit, then publish to Redis pub/sub."""
    await update_job_status(session, job_id, status, error_message=error_message)
    await session.commit()
    # Publish after commit so SSE consumers see the DB-committed state.
    await _publish_status(job_id, status, error_message)


# ── Task entry point ──────────────────────────────────────────────────────────

@celery_app.task(
    bind=True,
    name="workers.processing_tasks.process_scoresheet_task",
    max_retries=0,        # Surface errors immediately — no silent retries.
    time_limit=600,       # 10 min hard limit (TrOCR on CPU can be slow).
    soft_time_limit=540,  # 9 min soft limit (SoftTimeLimitExceeded raised).
)
def process_scoresheet_task(self, *, job_id: str, game_id: str) -> dict:  # type: ignore[override]
    """
    Full CV + OCR pipeline for one uploaded scoresheet.

    Args:
        job_id:  ProcessingJob.id (UUID string)
        game_id: Game.id (UUID string)

    Returns:
        dict with status and summary counts on success,
        or status="failed" with error message on any failure.

    Side effects:
        • Updates ProcessingJob.status (and Game.status) in PostgreSQL.
        • Writes MoveCrop + MoveEntry records for each non-blank cell.
        • Writes OCRResult records and updates MoveEntry fields.
        • Saves crop PNG files to storage.
    """
    logger.info("Task started — job_id=%s game_id=%s", job_id, game_id)
    return asyncio.run(_run_pipeline(job_id=job_id, game_id=game_id))


# ── task_failure signal ───────────────────────────────────────────────────────

@task_failure.connect(sender="workers.processing_tasks.process_scoresheet_task")
def on_process_scoresheet_failure(
    sender: Any = None,
    task_id: Optional[str] = None,
    exception: Optional[BaseException] = None,
    traceback: Any = None,
    einfo: Any = None,
    kwargs: Optional[dict] = None,
    **extras: Any,
) -> None:
    """
    Safety-net handler for hard-crash failures on process_scoresheet_task.

    Fires when an exception escapes the task function entirely — i.e., when
    the try/except in _run_pipeline was bypassed (e.g., _make_session() raises
    before the try block, or the asyncio.run() machinery itself errors out).

    Without this, a job whose task function never entered the except block
    would be left stuck in its last intermediate status ("preprocessing",
    "cropping", etc.) with no way to recover.

    Note: if _run_pipeline's own except block already set status to "failed",
    this handler runs a redundant UPDATE — harmless, but ensures correctness.
    """
    task_kwargs = kwargs or {}
    job_id: Optional[str] = task_kwargs.get("job_id")
    if not job_id:
        logger.warning(
            "task_failure signal received for task_id=%s but no job_id in kwargs",
            task_id,
        )
        return

    msg = f"Worker crash (task_failure signal): {type(exception).__name__}: {exception}"
    logger.error(
        "task_failure signal — task_id=%s job_id=%s error=%s", task_id, job_id, msg
    )

    async def _mark_failed() -> None:
        session = _make_session()
        try:
            await _set_status(session, job_id, "failed", error_message=msg)
        except Exception:  # noqa: BLE001
            logger.exception(
                "Could not mark job failed via task_failure signal — job_id=%s", job_id
            )
        finally:
            await session.close()

    asyncio.run(_mark_failed())


# ── Pipeline ──────────────────────────────────────────────────────────────────

async def _run_pipeline(*, job_id: str, game_id: str) -> dict:
    """Async pipeline body, invoked once per asyncio.run() call."""
    session = _make_session()
    storage = get_storage_cached()

    try:
        # ── Phase 3A: image preprocessing ────────────────────────────────────
        await _set_status(session, job_id, "preprocessing")

        image_bytes = await _load_image(session, game_id, storage)
        preprocess_result = ImagePreprocessor().run(image_bytes)
        logger.info("Preprocessing complete — game_id=%s", game_id)

        # ── Phase 3B: grid detection + crop extraction ────────────────────────
        await _set_status(session, job_id, "cropping")

        # Idempotent: delete any MoveEntry rows left by a previous crashed
        # attempt.  task_acks_late + reject_on_worker_lost means the broker
        # can redeliver this message to a fresh worker after a hard kill;
        # without this cleanup the INSERT in _persist_crops would hit the
        # UniqueConstraint on (game_id, ply_index) and fail.
        await _cleanup_stale_moves(session, game_id)

        detector = GridDetector(preprocess_result.binary)
        try:
            layout = detector.detect()
        except GridDetectionError as exc:
            msg = f"Grid detection failed: {exc}"
            logger.error("game_id=%s %s", game_id, msg)
            await _set_status(session, job_id, "failed", error_message=msg)
            return {"status": "failed", "error": msg}

        crops = CropExtractor(
            gray=preprocess_result.gray,
            binary=preprocess_result.binary,
            layout=layout,
        ).extract()

        non_blank = [c for c in crops if not c.is_blank]
        entry_ids = await _persist_crops(session, game_id, non_blank, storage)
        logger.info(
            "Cropping complete — game_id=%s crops=%d", game_id, len(non_blank)
        )

        # ── Phase 4: OCR ──────────────────────────────────────────────────────
        await _set_status(session, job_id, "ocr_processing")

        if non_blank:
            ocr_provider = _get_ocr_provider()
            crop_bytes = [c.image_bytes for c in non_blank]
            predictions = ocr_provider.recognise_batch(crop_bytes)
            await _persist_ocr_results(session, game_id, non_blank, entry_ids, predictions)
            logger.info(
                "OCR complete — game_id=%s predictions=%d", game_id, len(predictions)
            )
        else:
            logger.warning("No non-blank crops — OCR skipped for game_id=%s", game_id)

        await _set_status(session, job_id, "ocr_complete")
        logger.info(
            "OCR phase complete — game_id=%s crops=%d", game_id, len(non_blank)
        )

        # ── Phase 5: chess analysis ───────────────────────────────────────────
        await _set_status(session, job_id, "analyzing")
        return await _run_analysis(session, job_id, game_id)

    except Exception as exc:  # noqa: BLE001
        msg = f"Unexpected error in pipeline: {type(exc).__name__}: {exc}"
        logger.exception("Unhandled error — job_id=%s game_id=%s", job_id, game_id)
        try:
            await _set_status(session, job_id, "failed", error_message=msg)
        except Exception:  # noqa: BLE001
            logger.exception("Could not update job status after pipeline error")
        return {"status": "failed", "error": msg}

    finally:
        await session.close()


# ── Analysis phase ────────────────────────────────────────────────────────────

async def _run_analysis(
    session: AsyncSession,
    job_id: str,
    game_id: str,
) -> dict:
    """
    Phase 5: validate OCR texts against chess rules, run FIDE checks, write
    all results to DB, and mark the job complete.

    We set game.status directly from the chess-analysis outcome rather than
    routing through update_job_status, because update_job_status's
    game_status_map maps job-status "completed" → game-status "completed" and
    would silently overwrite a legitimate "needs_review" result.

    Returns:
        dict with status="completed", game_status, move_count, finding_count.

    Raises:
        Any unhandled exception — the caller's try/except sets job to "failed".
    """
    from datetime import datetime, timezone

    from sqlalchemy import select
    from sqlalchemy.orm import selectinload

    from models.game import Game, MoveEntry, ProcessingJob, RuleFindingDB
    from schemas.analysis import AnalysisSource, GameStatus, UploadMetadata
    from services.chess.chess_service import ChessService

    # ── Load move entries with OCR results, ordered by ply ───────────────────
    entries_stmt = (
        select(MoveEntry)
        .where(MoveEntry.game_id == game_id)
        .options(selectinload(MoveEntry.ocr_result))
        .order_by(MoveEntry.ply_index)
    )
    entries_result = await session.execute(entries_stmt)
    entries: List[Any] = list(entries_result.scalars().all())

    # ── Load game for locale + upload metadata ────────────────────────────────
    game_stmt = (
        select(Game)
        .where(Game.id == game_id)
        .options(selectinload(Game.uploaded_asset))
    )
    game_result = await session.execute(game_stmt)
    game = game_result.scalar_one_or_none()
    if game is None:
        raise RuntimeError(f"Game {game_id} not found during analysis phase")

    locale = game.locale or "en"
    upload_meta: Optional[UploadMetadata] = None
    if game.uploaded_asset:
        upload_meta = UploadMetadata(
            filename=game.uploaded_asset.original_filename,
            uploaded_at=game.uploaded_asset.created_at.isoformat(),
        )

    # ── Build raw_moves / ocr_confidences lists ───────────────────────────────
    # Entries are sorted by ply_index from the query; analysis.moves comes back
    # in the same order so zip() aligns them correctly.
    raw_moves: List[str] = []
    ocr_confidences: List[float] = []
    for entry in entries:
        if entry.ocr_result is not None:
            raw_moves.append(entry.ocr_result.normalized_text)
            ocr_confidences.append(entry.confidence)
        else:
            # OCR result missing — empty string causes matcher to flag illegal
            raw_moves.append("")
            ocr_confidences.append(0.0)

    # ── Run chess analysis ────────────────────────────────────────────────────
    chess_svc = ChessService()
    analysis = chess_svc.analyze_game(
        raw_moves=raw_moves,
        session_id=game.session_id,
        locale=locale,
        game_id=game_id,
        upload_metadata=upload_meta,
        ocr_confidences=ocr_confidences,
        analysis_source=AnalysisSource.OCR,
    )
    logger.info(
        "Chess analysis complete — game_id=%s analysis_status=%s "
        "moves=%d findings=%d",
        game_id,
        analysis.status.value,
        len(analysis.moves),
        len(analysis.findings),
    )

    # ── Write MoveEntry results back ──────────────────────────────────────────
    # zip() stops at the shorter side: if an illegal move terminates the game
    # early, analysis.moves will be shorter than entries — remaining entries
    # keep their OCR-only placeholder values (is_legal=False, needs_review=True).
    for entry, move_result in zip(entries, analysis.moves):
        entry.selected_san = move_result.selected_san
        entry.selected_uci = move_result.selected_uci
        entry.fen_before = move_result.fen_before
        entry.fen_after = move_result.fen_after
        entry.is_legal = move_result.is_legal
        entry.confidence = move_result.confidence
        entry.needs_review = move_result.needs_manual_review
        entry.fide_alerts_csv = ",".join(move_result.fide_alerts)

    # ── Create RuleFindingDB rows ─────────────────────────────────────────────
    for finding in analysis.findings:
        session.add(RuleFindingDB(
            game_id=game_id,
            ply_index=finding.ply_index,
            type=finding.type.value,
            description=finding.description,
            is_automatic=finding.is_automatic,
        ))

    # ── Update Game ───────────────────────────────────────────────────────────
    game.pgn = analysis.pgn
    game.failure_point_ply = analysis.failure_point_ply
    # Set game.status directly from analysis so "needs_review" is preserved.
    game.status = analysis.status.value

    # ── Mark ProcessingJob as completed ──────────────────────────────────────
    # Both COMPLETED and NEEDS_REVIEW → job status "completed".
    # Exception path is handled by the outer try/except in _run_pipeline.
    job_stmt = select(ProcessingJob).where(ProcessingJob.id == job_id)
    job_res = await session.execute(job_stmt)
    job = job_res.scalar_one_or_none()
    if job:
        job.status = "completed"
        job.completed_at = datetime.now(timezone.utc)

    await session.commit()

    # ── Publish final SSE "completed" event ───────────────────────────────────
    # The mobile client navigates to the game screen on "completed" and reads
    # game.status from there — so we always publish "completed" here.
    await _publish_status(job_id, "completed")

    return {
        "status": "completed",
        "game_status": analysis.status.value,
        "move_count": len(analysis.moves),
        "finding_count": len(analysis.findings),
    }


# ── Storage helpers ───────────────────────────────────────────────────────────

async def _cleanup_stale_moves(session: AsyncSession, game_id: str) -> None:
    """
    Delete any existing MoveEntry rows for *game_id* before re-running crop
    extraction.

    This makes _persist_crops idempotent: if the Celery task is redelivered
    after a hard worker crash (task_acks_late=True + reject_on_worker_lost=True),
    the new worker can safely recreate all rows without hitting the
    UniqueConstraint on (game_id, ply_index).

    MoveCrop and OCRResult rows are removed automatically via the
    cascade="all, delete-orphan" relationship on MoveEntry.
    """
    from sqlalchemy import delete
    from models.game import MoveEntry

    result = await session.execute(
        delete(MoveEntry).where(MoveEntry.game_id == game_id)
    )
    await session.commit()
    deleted = result.rowcount
    if deleted:
        logger.info(
            "Cleaned up %d stale MoveEntry rows for game_id=%s (idempotent retry)",
            deleted,
            game_id,
        )


async def _load_image(session: AsyncSession, game_id: str, storage: Any) -> bytes:
    """Fetch the uploaded image bytes from storage for this game."""
    from sqlalchemy import select
    from models.game import UploadedAsset

    stmt = select(UploadedAsset).where(UploadedAsset.game_id == game_id)
    result = await session.execute(stmt)
    asset = result.scalar_one_or_none()
    if asset is None:
        raise RuntimeError(f"No UploadedAsset found for game_id={game_id}")
    return await storage.load(asset.file_path)


async def _persist_crops(
    session: AsyncSession,
    game_id: str,
    crops: List[CropResult],
    storage: Any,
) -> List[str]:
    """
    Save crop PNGs to storage and create MoveEntry + MoveCrop DB rows.

    MoveEntry rows are created as placeholders (is_legal=False,
    needs_review=True, confidence=0.0).  Phase 4 fills in OCR fields;
    Phase 5 fills in chess validation fields.

    Returns:
        List of MoveEntry.id strings in the same order as *crops*.
    """
    from models.game import MoveEntry, MoveCrop

    entry_ids: List[str] = []

    for crop in crops:
        storage_key = f"crops/{game_id}/{crop.ply_index}.png"
        await storage.save(crop.image_bytes, storage_key, content_type="image/png")

        entry = MoveEntry(
            game_id=game_id,
            move_number=crop.move_number,
            ply_index=crop.ply_index,
            color=crop.color,
            fen_before="",  # filled in by Phase 5 (chess analysis)
            fen_after="",
            is_legal=False,
            needs_review=True,
            confidence=0.0,
        )
        session.add(entry)
        await session.flush()  # populate entry.id before FK references
        entry_ids.append(entry.id)

        x1, y1, x2, y2 = crop.source_region
        session.add(MoveCrop(
            move_entry_id=entry.id,
            crop_image_path=storage_key,
            bbox_x=x1,
            bbox_y=y1,
            bbox_w=x2 - x1,
            bbox_h=y2 - y1,
        ))

    await session.commit()
    logger.debug("Persisted %d crop records for game %s", len(crops), game_id)
    return entry_ids


# ── OCR helpers ───────────────────────────────────────────────────────────────

def _get_ocr_provider() -> OCRProvider:
    """
    Return the configured OCR provider (reads settings.OCR_BACKEND).

    "trocr"      → TrOCRProvider  (production)
    "tesseract"  → TesseractProvider  (dev/comparison — see tesseract.py)
    """
    backend = settings.OCR_BACKEND.lower()
    if backend == "trocr":
        from services.ocr.trocr import get_trocr_provider
        return get_trocr_provider()
    if backend == "tesseract":
        from services.ocr.tesseract import TesseractProvider
        logger.warning(
            "OCR_BACKEND=tesseract — this is dev/comparison mode, "
            "not suitable for production."
        )
        return TesseractProvider()
    raise ValueError(
        f"Unknown OCR_BACKEND={backend!r}. "
        "Valid values: 'trocr' (production) | 'tesseract' (dev only)."
    )


async def _persist_ocr_results(
    session: AsyncSession,
    game_id: str,
    crops: List[CropResult],
    entry_ids: List[str],
    predictions: List[OCRPrediction],
) -> None:
    """
    Write OCRResult rows and update the corresponding MoveEntry fields.

    Args:
        crops:       Non-blank CropResult list (defines ply order).
        entry_ids:   MoveEntry IDs in the same order as *crops*.
        predictions: OCRPrediction from the provider, same order as *crops*.
    """
    from sqlalchemy import select
    from models.game import MoveEntry, OCRResult

    for entry_id, crop, pred in zip(entry_ids, crops, predictions):
        # ── Write OCRResult ───────────────────────────────────────────────────
        candidates_json = [
            {"text": c.text, "confidence": c.confidence}
            for c in pred.candidates
        ]
        ocr_row = OCRResult(
            move_entry_id=entry_id,
            raw_text=pred.raw_text,
            candidates_json=candidates_json,
            normalized_text=pred.raw_text,   # normalizer runs in Phase 5
        )
        session.add(ocr_row)

        # ── Update MoveEntry with top-1 OCR confidence ────────────────────────
        stmt = select(MoveEntry).where(MoveEntry.id == entry_id)
        result = await session.execute(stmt)
        entry = result.scalar_one_or_none()
        if entry is not None:
            entry.confidence = pred.candidates[0].confidence
            # Flag for manual review if confidence is below threshold
            entry.needs_review = (
                pred.candidates[0].confidence < settings.OCR_CONFIDENCE_THRESHOLD
            )

    await session.commit()
    logger.debug(
        "Persisted %d OCR results for game %s", len(predictions), game_id
    )
