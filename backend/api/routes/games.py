"""
/api/games — game analysis, retrieval, and listing routes.

Phase 1 endpoint (stateless, no DB):
  POST /api/games/analyze        Accept a raw move list, return annotated game

Phase 2 endpoints (DB-backed):
  GET  /api/games/{game_id}      Fetch a stored game by ID
  GET  /api/games/               List games for a session

Phase 6+ endpoint (stub):
  POST /api/games/{game_id}/moves/{ply_index}/correct
"""

from __future__ import annotations

import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from schemas.analysis import AnalyzeMoveListRequest, GameAnalysisResponse
from schemas.upload import GameSummary
from services.chess.chess_service import ChessService
from services.job_service import (
    game_to_response,
    game_to_summary,
    get_game_full,
    get_games_by_session,
)

logger = logging.getLogger(__name__)

router = APIRouter()

# Single shared instance — ChessService is stateless between requests
_chess_service = ChessService()


# ── Phase 1: stateless analysis ───────────────────────────────────────────────


@router.post(
    "/analyze",
    response_model=GameAnalysisResponse,
    status_code=status.HTTP_200_OK,
    summary="Analyze a raw move list (Phase 1)",
    description=(
        "Accepts an ordered list of SAN move strings (White then Black alternating), "
        "validates each move against the legal board state using python-chess, "
        "applies all FIDE draw and termination rules, and returns a fully annotated "
        "game record.\n\n"
        "**Phase 1 only** — does not persist to the database. "
        "In production, analysis is triggered automatically after the OCR pipeline "
        "completes; use the upload endpoint and SSE for the full flow."
    ),
)
async def analyze_move_list(request: AnalyzeMoveListRequest) -> GameAnalysisResponse:
    try:
        return _chess_service.analyze_game(
            raw_moves=request.moves,
            session_id=request.session_id,
            locale=request.locale,
            analysis_source=request.analysis_source,
        )
    except Exception as exc:
        # Don't leak internal exception text to the client (info disclosure).
        logger.exception("Move-list analysis failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Analysis failed due to an internal error.",
        ) from exc


# ── Phase 2: DB-backed retrieval ────────────────────────────���─────────────────


@router.get(
    "/{game_id}",
    response_model=GameAnalysisResponse,
    summary="Get a game by ID",
    description=(
        "Fetch a stored game and its full analysis results.\n\n"
        "If the game is still processing (`status` is `processing`), "
        "the `moves` and `findings` arrays will be empty — poll again "
        "or use the SSE endpoint for real-time updates.\n\n"
        "Returns 404 if the game_id does not exist."
    ),
    responses={
        200: {"description": "Game found and returned."},
        404: {"description": "Game not found."},
    },
)
async def get_game(
    game_id: str,
    session_id: str = Query(..., description="Anonymous session that owns the game"),
    db: AsyncSession = Depends(get_db),
) -> GameAnalysisResponse:
    game = await get_game_full(db, game_id)
    # Ownership check: a game is only visible to the session that created it.
    # Return 404 (not 403) on mismatch so we don't confirm the id exists.
    if game is None or game.session_id != session_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Game '{game_id}' not found.",
        )
    return game_to_response(game)


@router.get(
    "/",
    response_model=List[GameSummary],
    summary="List games for a session",
    description=(
        "Returns lightweight game summaries (no move detail) for an anonymous session.\n\n"
        "Pass the same `session_id` used during upload to retrieve the session's history."
    ),
)
async def list_games(
    session_id: str = Query(..., description="Anonymous session UUID"),
    limit: int = Query(default=50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
) -> List[GameSummary]:
    games = await get_games_by_session(db, session_id, limit=limit)
    return [game_to_summary(g) for g in games]
