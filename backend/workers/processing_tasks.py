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

@task_failure.connect(sender=process_scoresheet_task)
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
        from models.game import ProcessingJob
        job = await session.get(ProcessingJob, job_id)
        if job is None or job.game_id != game_id:
            raise ValueError("Processing job does not belong to this game.")
        if job.status in {"completed", "failed"}:
            return {"status": job.status, "skipped": True}
        # ── Phase 3A: image preprocessing ────────────────────────────────────
        await _set_status(session, job_id, "preprocessing")

        image_bytes = await _load_image(session, game_id, storage)
        if image_bytes.startswith(b"%PDF-"):
            from services.pdf_renderer import render_pdf
            image_bytes = render_pdf(image_bytes)
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
            if settings.OCR_BACKEND.lower() == "claude":
                # Claude reads the full sheet directly, so missing grid lines
                # only cost us the per-move crop images for the review UI.
                logger.warning(
                    "Grid detection failed (%s) — continuing without crops "
                    "via Claude full-sheet OCR. game_id=%s", exc, game_id,
                )
                layout = None
            else:
                msg = f"Grid detection failed: {exc}"
                logger.error("game_id=%s %s", game_id, msg)
                await _set_status(session, job_id, "failed", error_message=msg)
                return {"status": "failed", "error": msg}

        if layout is not None:
            crops = CropExtractor(
                gray=preprocess_result.gray,
                binary=preprocess_result.binary,
                layout=layout,
            ).extract()
            non_blank = [c for c in crops if not c.is_blank]
        else:
            non_blank = []

        entry_ids = await _persist_crops(session, game_id, non_blank, storage)
        logger.info(
            "Cropping complete — game_id=%s crops=%d", game_id, len(non_blank)
        )

        # ── Phase 4: OCR ──────────────────────────────────────────────────────
        await _set_status(session, job_id, "ocr_processing")

        ocr_done = False
        if settings.OCR_BACKEND.lower() == "claude":
            ocr_done = await _run_claude_sheet_ocr(
                session, game_id, image_bytes, non_blank, entry_ids
            )

        if not ocr_done:
            # Per-crop path: TrOCR/Tesseract, or fallback after a Claude failure.
            if non_blank:
                ocr_provider = _get_ocr_provider(allow_claude=False)
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
            await session.rollback()
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

    from sqlalchemy import delete, select
    from sqlalchemy.orm import selectinload

    from models.game import Game, MoveEntry, ProcessingJob, RuleFindingDB
    from schemas.analysis import AnalysisSource, GameStatus, UploadMetadata
    from services.chess.chess_service import ChessService
    from services.move_sequence import apply_move_analysis, ensure_move_sequence, ocr_input, status_for_entries

    # ── Load move entries with OCR results, ordered by ply ───────────────────
    entries_stmt = (
        select(MoveEntry)
        .where(MoveEntry.game_id == game_id)
        .options(selectinload(MoveEntry.ocr_result))
        .order_by(MoveEntry.ply_index)
    )
    entries_result = await session.execute(entries_stmt)
    entries: List[Any] = list(entries_result.scalars().all())
    entries = await ensure_move_sequence(session, game_id, entries)
    if not entries:
        raise ValueError("No handwritten moves were found on the scoresheet.")

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
    # Missing cells remain explicit slots; never compact the move sequence.
    raw_moves: List[str] = []
    ocr_confidences: List[float] = []
    for entry in entries:
        text, confidence = ocr_input(entry, locale)
        raw_moves.append(text)
        ocr_confidences.append(confidence)
        if entry.ocr_result is not None:
            entry.ocr_result.normalized_text = text

    # ── Run chess analysis ────────────────────────────────────────────────────
    chess_svc = ChessService()
    analysis = chess_svc.analyze_game(
        raw_moves=raw_moves,
        session_id=game.session_id,
        locale="en",
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
    apply_move_analysis(entries, analysis)

    # ── Create RuleFindingDB rows ─────────────────────────────────────────────
    # Clear any rows left by a previous (crashed) attempt before inserting fresh
    # ones. task_acks_late + reject_on_worker_lost allows task redelivery, so
    # this function may run more than once for the same game_id.
    from sqlalchemy import delete
    await session.execute(delete(RuleFindingDB).where(RuleFindingDB.game_id == game_id))
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
    game.status = status_for_entries(entries).value

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
        "game_status": game.status,
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

def _get_ocr_provider(allow_claude: bool = True) -> OCRProvider:
    """
    Return the configured OCR provider (reads settings.OCR_BACKEND).

    "claude"     → ClaudeVisionProvider  (production, highest accuracy)
    "trocr"      → TrOCRProvider  (offline fallback)
    "tesseract"  → TesseractProvider  (dev/comparison — see tesseract.py)

    Args:
        allow_claude: False forces the local fallback chain — used after a
            Claude API failure so the retry never loops back to Claude.
    """
    backend = settings.OCR_BACKEND.lower()
    if backend == "claude" and not allow_claude:
        backend = "trocr"
    if backend == "claude":
        from services.ocr.claude_vision import get_claude_provider
        return get_claude_provider()
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
        "Valid values: 'claude' (production) | 'trocr' | 'tesseract' (dev only)."
    )


async def _run_claude_sheet_ocr(
    session: AsyncSession,
    game_id: str,
    image_bytes: bytes,
    crops: List[CropResult],
    entry_ids: List[str],
) -> bool:
    """
    Full-sheet OCR via the Claude API and persistence of the results.

    The whole scoresheet image is read in one API call; readings are aligned
    to the previously persisted crop entries by ply_index.  Moves Claude read
    that have NO matching crop (blank-detection false positives, or grid
    detection failed entirely) get their own MoveEntry rows so the chess
    analysis still sees the complete game.

    Returns:
        True  — Claude OCR succeeded and results are persisted.
        False — Claude failed and the caller should run the TrOCR fallback
                over the crops (only possible when crops exist).

    Raises:
        ClaudeVisionError: Claude failed and no fallback is viable
            (OCR_FALLBACK_TO_TROCR=false, or there are no crops to re-read).
    """
    from services.ocr.claude_vision import (
        ClaudeVisionError,
        blank_prediction,
        get_claude_provider,
        sheet_move_to_prediction,
    )

    provider = get_claude_provider()
    try:
        sheet_moves = provider.recognise_sheet(image_bytes)
    except ClaudeVisionError as exc:
        if settings.OCR_FALLBACK_TO_TROCR and crops:
            logger.error(
                "Claude OCR failed — falling back to TrOCR. game_id=%s error=%s",
                game_id, exc,
            )
            return False
        raise

    by_ply = {m.ply_index: m for m in sheet_moves}

    # ── Crop-aligned predictions ──────────────────────────────────────────────
    predictions: List[OCRPrediction] = []
    for crop in crops:
        move = by_ply.pop(crop.ply_index, None)
        if move is not None:
            predictions.append(sheet_move_to_prediction(move, provider.provider_name))
        else:
            predictions.append(blank_prediction(provider.provider_name))
    if crops:
        await _persist_ocr_results(session, game_id, crops, entry_ids, predictions)

    # ── Moves without a crop (false-blank cells / grid failure) ──────────────
    extra = [by_ply[p] for p in sorted(by_ply)]
    if extra:
        await _persist_cropless_moves(session, game_id, extra, provider.provider_name)

    logger.info(
        "Claude OCR complete — game_id=%s crop_aligned=%d cropless=%d",
        game_id, len(crops), len(extra),
    )
    return True


async def _persist_cropless_moves(
    session: AsyncSession,
    game_id: str,
    moves: List[Any],
    provider_name: str,
) -> None:
    """Create MoveEntry + OCRResult rows for sheet moves that have no crop image."""
    from services.ocr.claude_vision import sheet_move_to_prediction
    from models.game import MoveEntry, OCRResult

    for move in moves:
        entry = MoveEntry(
            game_id=game_id,
            move_number=move.move_number,
            ply_index=move.ply_index,
            color=move.color,
            fen_before="",
            fen_after="",
            is_legal=False,
            needs_review=move.confidence < settings.OCR_CONFIDENCE_THRESHOLD,
            confidence=move.confidence,
        )
        session.add(entry)
        await session.flush()

        pred = sheet_move_to_prediction(move, provider_name)
        session.add(OCRResult(
            move_entry_id=entry.id,
            raw_text=pred.raw_text,
            candidates_json=[
                {"text": c.text, "confidence": c.confidence} for c in pred.candidates
            ],
            normalized_text=pred.raw_text,
        ))

    await session.commit()


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

    # Bulk-load all MoveEntry rows in one query instead of N individual SELECTs.
    bulk_stmt = select(MoveEntry).where(MoveEntry.id.in_(entry_ids))
    bulk_result = await session.execute(bulk_stmt)
    entries_by_id = {e.id: e for e in bulk_result.scalars().all()}

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
            notation_locale=pred.notation_locale,
        )
        session.add(ocr_row)

        # ── Update MoveEntry with top-1 OCR confidence ────────────────────────
        entry = entries_by_id.get(entry_id)
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
