"""
Job and Game CRUD operations.

This service mediates between route handlers and the database.
It owns the logic for:
  - Creating a game + associated upload asset + processing job (atomic)
  - Reading a game with all related data for GET /api/games/{id}
  - Updating job status (used by Celery workers in Phase 4+)
  - Listing games by session

All methods take an AsyncSession and do NOT commit — the caller (route handler
or Depends(get_db)) is responsible for the commit so transactions are scoped
correctly to the HTTP request.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from config import settings
from models.game import (
    Game,
    MoveEntry,
    ProcessingJob,
    RuleFindingDB,
    UploadedAsset,
)
from schemas.analysis import (
    DrawDecision,
    FindingType,
    GameAnalysisResponse,
    GameStats,
    GameStatus,
    MoveAnalysis,
    OCRCandidate,
    ReviewReason,
    RuleFinding,
    UploadMetadata,
)
from schemas.upload import GameSummary
from services.chess.chess_service import check_square_from_fen
from security import sign_storage_key

logger = logging.getLogger(__name__)


# ── Creation ──────────────────────────────────────────────────────────────────


async def create_game_with_upload(
    db: AsyncSession,
    *,
    session_id: str,
    locale: str,
    file_path: str,
    file_type: str,
    original_filename: Optional[str],
    file_size_bytes: int,
) -> tuple[Game, UploadedAsset, ProcessingJob]:
    """
    Atomically create a Game, its UploadedAsset, and a ProcessingJob.

    Called by the upload route handler.  All three records are added in the same
    DB transaction — the caller's get_db() dependency commits on success.

    Returns:
        (game, asset, job) — all flushed but not yet committed.
    """
    game = Game(
        session_id=session_id,
        status=GameStatus.PROCESSING.value,
        locale=locale,
    )
    db.add(game)
    await db.flush()  # populate game.id before FK references

    asset = UploadedAsset(
        game_id=game.id,
        file_path=file_path,
        file_type=file_type,
        original_filename=original_filename,
        file_size_bytes=file_size_bytes,
    )
    db.add(asset)

    job = ProcessingJob(
        game_id=game.id,
        status="queued",
    )
    db.add(job)

    await db.flush()
    logger.info("Created Game %s | Job %s | Asset %s", game.id, job.id, asset.id)
    return game, asset, job


# ── Reading ───────────────────────────────────────────────────────────────────


async def get_game_full(
    db: AsyncSession, game_id: str
) -> Optional[Game]:
    """
    Load a Game with all eagerly-loaded relationships needed for the API response.

    Returns None if not found.
    """
    stmt = (
        select(Game)
        .where(Game.id == game_id)
        .options(
            selectinload(Game.uploaded_asset),
            selectinload(Game.processing_job),
            selectinload(Game.move_entries).selectinload(MoveEntry.ocr_result),
            selectinload(Game.move_entries).selectinload(MoveEntry.crop),
            selectinload(Game.rule_findings),
        )
    )
    result = await db.execute(stmt)
    return result.scalar_one_or_none()


async def get_games_by_session(
    db: AsyncSession, session_id: str, limit: int = 50
) -> List[Game]:
    """Return the most recent games for a session (newest first)."""
    stmt = (
        select(Game)
        .where(Game.session_id == session_id)
        .options(
            selectinload(Game.uploaded_asset),
            selectinload(Game.processing_job),
            selectinload(Game.move_entries),
            selectinload(Game.rule_findings),
        )
        .order_by(Game.created_at.desc())
        .limit(limit)
    )
    result = await db.execute(stmt)
    return list(result.scalars().all())


# ── Updates ───────────────────────────────────────────────────────────────────


async def update_job_status(
    db: AsyncSession,
    job_id: str,
    status: str,
    celery_task_id: Optional[str] = None,
    error_message: Optional[str] = None,
) -> Optional[ProcessingJob]:
    """Update job status. Also updates Game.status to stay in sync."""
    stmt = select(ProcessingJob).where(ProcessingJob.id == job_id)
    result = await db.execute(stmt)
    job = result.scalar_one_or_none()
    if job is None:
        return None

    job.status = status
    if celery_task_id:
        job.celery_task_id = celery_task_id
    if error_message:
        job.error_message = error_message

    now = datetime.now(timezone.utc)
    # Set started_at on the first active status (idempotent).
    _active_statuses = {
        "preprocessing", "cropping", "awaiting_ocr",
        "ocr_processing", "ocr_complete",
        "ocr", "analyzing",
    }
    if status in _active_statuses:
        if job.started_at is None:
            job.started_at = now
    elif status in ("completed", "failed"):
        job.completed_at = now

    # Mirror the most meaningful status into Game.status.
    # All in-progress statuses → PROCESSING; only terminal statuses differ.
    game_status_map = {
        "queued":        GameStatus.PROCESSING.value,
        "preprocessing": GameStatus.PROCESSING.value,
        "cropping":      GameStatus.PROCESSING.value,
        "awaiting_ocr":  GameStatus.PROCESSING.value,
        "ocr_processing": GameStatus.PROCESSING.value,
        "ocr_complete":  GameStatus.PROCESSING.value,
        "ocr":           GameStatus.PROCESSING.value,
        "analyzing":     GameStatus.PROCESSING.value,
        "completed":     GameStatus.COMPLETED.value,
        "failed":        GameStatus.FAILED.value,
    }
    if status in game_status_map:
        game_stmt = select(Game).where(Game.id == job.game_id)
        game_result = await db.execute(game_stmt)
        game = game_result.scalar_one_or_none()
        if game:
            game.status = game_status_map[status]

    await db.flush()
    return job


# ── ORM → Pydantic conversion ─────────────────────────────────────────────────


def _derive_review_reasons(
    *,
    is_legal: bool,
    needs_review: bool,
    confidence: float,
) -> List[ReviewReason]:
    if not needs_review:
        return []
    if not is_legal:
        return [ReviewReason.ILLEGAL_MOVE]
    if confidence < settings.OCR_CONFIDENCE_THRESHOLD:
        return [ReviewReason.BELOW_THRESHOLD]
    return [ReviewReason.LEGACY_NEEDS_REVIEW]


def _compute_draw_summary(
    findings: List[RuleFinding],
) -> tuple[DrawDecision, Optional[str], bool, bool]:
    automatic_draw_types = {
        FindingType.FIVEFOLD_AUTOMATIC,
        FindingType.SEVENTY_FIVE_AUTOMATIC,
        FindingType.STALEMATE,
        FindingType.INSUFFICIENT_MATERIAL,
    }
    claimable_draw_types = {
        FindingType.THREEFOLD_CLAIM_AVAILABLE,
        FindingType.FIFTY_CLAIM_AVAILABLE,
    }

    for finding in findings:
        if finding.type in automatic_draw_types:
            return DrawDecision.AUTOMATIC_DRAW, finding.type.value, True, False

    for finding in findings:
        if finding.type in claimable_draw_types:
            return DrawDecision.CLAIMABLE_DRAW, finding.type.value, False, True

    return DrawDecision.NONE, None, False, False


def game_to_response(game: Game) -> GameAnalysisResponse:
    """
    Convert a fully-loaded Game ORM object to the API response schema.

    For games not yet processed (status=processing/queued), moves and findings
    are empty — this is the correct state for a freshly uploaded game.
    """
    moves: List[MoveAnalysis] = []
    for entry in game.move_entries:
        ocr = entry.ocr_result

        if ocr is not None:
            raw_text = ocr.raw_text
            candidates = [
                OCRCandidate(**c) for c in (ocr.candidates_json or [])
            ]
            normalized_text = ocr.normalized_text
        else:
            # Phase 2: no OCR yet — placeholder values
            raw_text = entry.selected_san or ""
            candidates = [OCRCandidate(text=raw_text, confidence=entry.confidence)]
            normalized_text = raw_text

        crop_url: Optional[str] = None
        if entry.crop is not None:
            # Short-lived signed URL — re-issued each time the game is fetched.
            crop_url = sign_storage_key(entry.crop.crop_image_path)

        moves.append(MoveAnalysis(
            move_number=entry.move_number,
            ply_index=entry.ply_index,
            color=entry.color,
            ocr_raw_text=raw_text,
            ocr_candidates=candidates,
            normalized_text=normalized_text,
            selected_san=entry.selected_san,
            selected_uci=entry.selected_uci,
            fen_before=entry.fen_before,
            fen_after=entry.fen_after,
            is_legal=entry.is_legal,
            needs_manual_review=entry.needs_review,
            confidence=entry.confidence,
            review_reasons=_derive_review_reasons(
                is_legal=entry.is_legal,
                needs_review=entry.needs_review,
                confidence=entry.confidence,
            ),
            fide_alerts=(
                [a for a in entry.fide_alerts_csv.split(",") if a]
                if entry.fide_alerts_csv else []
            ),
            crop_image_url=crop_url,
            check_square=(
                check_square_from_fen(entry.fen_after)
                if entry.is_legal and entry.fen_after else None
            ),
        ))

    findings: List[RuleFinding] = [
        RuleFinding(
            type=FindingType(f.type),
            ply_index=f.ply_index,
            description=f.description,
            is_automatic=f.is_automatic,
        )
        for f in game.rule_findings
    ]

    draw_decision, draw_reason, arbiter_must_end, requires_player_claim = (
        _compute_draw_summary(findings)
    )

    upload_meta = UploadMetadata(
        filename=(
            game.uploaded_asset.original_filename
            if game.uploaded_asset else None
        ),
        uploaded_at=(
            game.uploaded_asset.created_at.isoformat()
            if game.uploaded_asset else None
        ),
    )

    # Derive stats from move entries
    total = len(moves)
    review_required = sum(1 for m in moves if m.needs_manual_review)
    illegal = sum(1 for m in moves if not m.is_legal)
    avg_conf = sum(m.confidence for m in moves) / total if total > 0 else 0.0

    stats = GameStats(
        total_moves=total,
        auto_resolved=total - review_required,
        manual_review_required=review_required,
        illegal_moves=illegal,
        ocr_avg_confidence=round(avg_conf, 4),
    )

    return GameAnalysisResponse(
        game_id=game.id,
        session_id=game.session_id,
        locale=game.locale or "en",
        status=GameStatus(game.status),
        upload_metadata=upload_meta,
        moves=moves,
        findings=findings,
        pgn=game.pgn or "",
        failure_point_ply=game.failure_point_ply,
        processing_error=(
            game.processing_job.error_message if game.processing_job else None
        ),
        stats=stats,
        draw_decision=draw_decision,
        draw_reason=draw_reason,
        arbiter_must_end=arbiter_must_end,
        requires_player_claim=requires_player_claim,
    )


def game_to_summary(game: Game) -> GameSummary:
    return GameSummary(
        game_id=game.id,
        session_id=game.session_id,
        status=game.status,
        locale=game.locale,
        created_at=game.created_at.isoformat(),
        total_moves=len(game.move_entries) if game.move_entries else None,
        has_findings=bool(game.rule_findings),
        upload_filename=(
            game.uploaded_asset.original_filename if game.uploaded_asset else None
        ),
    )
