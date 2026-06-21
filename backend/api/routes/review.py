"""
Phase 6: Manual correction API.

POST /api/games/{game_id}/moves/{ply_index}/correct

Flow:
  1. Load the game + all move entries from the database.
  2. Reconstruct the board state up to (but not including) ply_index by
     replaying the already-confirmed selected_san values.
  3. Normalize and validate the corrected SAN against that board state.
     Returns 422 if the corrected move is not legal in the position.
  4. Build the full move list for re-analysis:
       plies 0 .. ply_index-1 : selected_san (already canonical English SAN)
       ply ply_index           : corrected_san (canonical English SAN)
       plies ply_index+1 .. N  : original OCR text normalized with game.locale
  5. Run chess_service.analyze_game() on the full list.
  6. Persist a ReviewAction record for the corrected ply.
  7. Update every MoveEntry row from ply_index onward with the new analysis.
     MoveEntry rows for plies that no longer exist (game ended earlier) are
     deleted.
  8. Replace RuleFindingDB rows from ply_index onward with the new findings.
  9. Update Game.status / .pgn / .failure_point_ply.
 10. Return the updated GameAnalysisResponse.

Rules enforced here:
  - DB records for plies 0 .. ply_index-1 are NEVER modified.
  - The corrected SAN is always validated against the actual board state;
    the client-supplied value is never trusted directly.
"""

from __future__ import annotations

from typing import List, Optional, Tuple

import chess
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy import select

from database import get_db
from models.game import Game, MoveEntry, ReviewAction, RuleFindingDB
from schemas.analysis import (
    AnalysisSource,
    GameAnalysisResponse,
    ManualCorrectionRequest,
    UploadMetadata,
)
from services.chess.chess_service import ChessService
from services.chess.normalizer import MoveNormalizer

router = APIRouter()

_chess_service = ChessService()
_normalizer = MoveNormalizer()


# ── Endpoint ──────────────────────────────────────────────────────────────────


@router.post(
    "/{game_id}/moves/{ply_index}/correct",
    response_model=GameAnalysisResponse,
    status_code=status.HTTP_200_OK,
    summary="Correct a move and re-analyze from that point (Phase 6)",
    description=(
        "Submit a manual correction for a specific ply.  The corrected SAN is "
        "validated against the actual board state before any changes are made.\n\n"
        "Re-analysis runs from `ply_index` onward — earlier moves are untouched.\n\n"
        "Returns 404 when `game_id` or `ply_index` does not exist, "
        "422 when `corrected_san` is not a legal move in the position."
    ),
    responses={
        200: {"description": "Correction accepted; updated game returned."},
        404: {"description": "Game or ply not found."},
        422: {"description": "Corrected SAN is not a legal move in this position."},
    },
)
async def correct_move(
    game_id: str,
    ply_index: int,
    request: ManualCorrectionRequest,
    db: AsyncSession = Depends(get_db),
) -> GameAnalysisResponse:
    # ── 1. Load game ──────────────────────────────────────────────────────────
    stmt = (
        select(Game)
        .where(Game.id == game_id)
        .options(
            selectinload(Game.uploaded_asset),
            selectinload(Game.move_entries).selectinload(MoveEntry.ocr_result),
            selectinload(Game.move_entries).selectinload(MoveEntry.crop),
            selectinload(Game.rule_findings),
        )
    )
    result = await db.execute(stmt)
    game = result.scalar_one_or_none()
    if game is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Game '{game_id}' not found.",
        )

    entries: List[MoveEntry] = sorted(game.move_entries, key=lambda e: e.ply_index)

    # ── 2. Locate the target entry ────────────────────────────────────────────
    target = next((e for e in entries if e.ply_index == ply_index), None)
    if target is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No move at ply_index={ply_index} for game '{game_id}'.",
        )

    game_locale = game.locale or request.locale or "en"

    # ── 3. Reconstruct board state up to ply_index ────────────────────────────
    board = chess.Board()
    for entry in entries:
        if entry.ply_index >= ply_index:
            break
        if not entry.selected_san:
            # Illegal/unresolved move before the correction point — game should
            # not have entries after this, but guard defensively.
            break
        try:
            board.push_san(entry.selected_san)
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    f"Could not reconstruct board at ply {entry.ply_index} "
                    f"(san={entry.selected_san!r}): {exc}"
                ),
            ) from exc

    # ── 4. Validate corrected SAN ─────────────────────────────────────────────
    canonical_san = _canonicalize_corrected_san(
        board=board,
        corrected_san=request.corrected_san,
        game_locale=game_locale,
        request_locale=request.locale,
    )
    if canonical_san is None:
        attempted = ", ".join(
            _candidate_normalizations(
                request.corrected_san,
                game_locale=game_locale,
                request_locale=request.locale,
            )
        )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Corrected move '{request.corrected_san}' "
                f"(normalized attempts: {attempted}) is not a legal move in this position. "
                f"Legal moves include: {', '.join(sorted(board.san(m) for m in board.legal_moves)[:8])}…"
            ),
        )

    # ── 5. Build full move list for re-analysis ───────────────────────────────
    raw_moves, ocr_confidences = _build_move_list(
        entries,
        ply_index,
        canonical_san,
        game_locale=game_locale,
    )

    # ── 6. Re-analyze ─────────────────────────────────────────────────────────
    # raw_moves is deliberately canonical English SAN here.  Earlier confirmed
    # moves are already English, and later OCR moves were normalized with
    # game_locale in _build_move_list.  Running with locale="en" prevents
    # Turkish K/Ş/V/A/F remapping from corrupting confirmed English SAN.
    analysis = _chess_service.analyze_game(
        raw_moves=raw_moves,
        session_id=game.session_id,
        locale="en",
        game_id=game.id,
        ocr_confidences=ocr_confidences,
        analysis_source=AnalysisSource.OCR,
    )

    # ── 7. Persist ReviewAction ───────────────────────────────────────────────
    db.add(ReviewAction(
        move_entry_id=target.id,
        original_san=target.selected_san or "",
        corrected_san=canonical_san,
    ))

    # ── 8. Update MoveEntry rows from ply_index onward ────────────────────────
    analysis_by_ply = {m.ply_index: m for m in analysis.moves}
    entries_to_touch = [e for e in entries if e.ply_index >= ply_index]

    for entry in entries_to_touch:
        a = analysis_by_ply.get(entry.ply_index)
        if a is None:
            # New game ends before this ply — delete the stale row.
            await db.delete(entry)
            continue
        entry.selected_san = a.selected_san
        entry.selected_uci = a.selected_uci
        entry.fen_before = a.fen_before
        entry.fen_after = a.fen_after
        entry.is_legal = a.is_legal
        entry.needs_review = a.needs_manual_review
        entry.confidence = a.confidence
        entry.fide_alerts_csv = ",".join(a.fide_alerts)

    # ── 9. Replace RuleFindingDB rows from ply_index onward ───────────────────
    await db.execute(
        delete(RuleFindingDB)
        .where(RuleFindingDB.game_id == game_id)
        .where(RuleFindingDB.ply_index >= ply_index)
    )
    for finding in analysis.findings:
        if finding.ply_index >= ply_index:
            db.add(RuleFindingDB(
                game_id=game_id,
                ply_index=finding.ply_index,
                type=finding.type.value,
                description=finding.description,
                is_automatic=finding.is_automatic,
            ))

    # ── 10. Update Game metadata ──────────────────────────────────────────────
    game.pgn = analysis.pgn
    game.failure_point_ply = analysis.failure_point_ply
    game.status = analysis.status.value

    await db.flush()

    # ── 11. Return response ───────────────────────────────────────────────────
    # Return the re-analysis result with the correct upload metadata from DB.
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
    return analysis.model_copy(update={
        "locale": game_locale,
        "upload_metadata": upload_meta,
    })


# ── Helpers ───────────────────────────────────────────────────────────────────


def _build_move_list(
    entries: List[MoveEntry],
    ply_index: int,
    canonical_san: str,
    *,
    game_locale: str,
) -> Tuple[List[str], List[float]]:
    """
    Build the (raw_moves, ocr_confidences) lists for a full re-analysis.

    Plies < ply_index : use selected_san  + confidence 1.0 (canonical English)
    Ply  == ply_index : use canonical_san + confidence 1.0 (canonical English)
    Plies > ply_index : use original OCR raw text normalized with game_locale
    """
    raw_moves: List[str] = []
    ocr_confidences: List[float] = []

    for entry in entries:
        if entry.ply_index < ply_index:
            raw_moves.append(entry.selected_san or "")
            ocr_confidences.append(1.0)
        elif entry.ply_index == ply_index:
            raw_moves.append(canonical_san)
            ocr_confidences.append(1.0)
        else:
            # Subsequent move: use original OCR text for re-matching against
            # the updated board state.
            if entry.ocr_result is not None:
                raw_moves.append(
                    _normalizer.normalize(entry.ocr_result.raw_text, game_locale)
                )
                cands = entry.ocr_result.candidates_json
                conf = float(cands[0]["confidence"]) if cands else entry.confidence
            else:
                raw_moves.append(entry.selected_san or "")
                conf = entry.confidence
            ocr_confidences.append(conf)

    return raw_moves, ocr_confidences


def _candidate_normalizations(
    corrected_san: str,
    *,
    game_locale: str,
    request_locale: str,
) -> List[str]:
    """
    Try English first because UI-selected moves are canonical SAN.  Then try the
    game/request locales so manually typed Turkish notation such as Vh4+ still
    validates.
    """
    locales: List[str] = []
    for locale in ("en", game_locale, request_locale):
        if locale and locale not in locales:
            locales.append(locale)

    normalized: List[str] = []
    for locale in locales:
        value = _normalizer.normalize(corrected_san, locale)
        if value not in normalized:
            normalized.append(value)
    return normalized


def _canonicalize_corrected_san(
    *,
    board: chess.Board,
    corrected_san: str,
    game_locale: str,
    request_locale: str,
) -> Optional[str]:
    for normalized in _candidate_normalizations(
        corrected_san,
        game_locale=game_locale,
        request_locale=request_locale,
    ):
        try:
            move = board.parse_san(normalized)
            if move in board.legal_moves:
                return board.san(move)
        except Exception:
            continue
    return None
