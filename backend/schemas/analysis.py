"""
Pydantic v2 schemas for game analysis requests and responses.

These are the canonical API contracts used by:
  - api/routes/games.py  (request parsing, response serialization)
  - services/chess/chess_service.py  (builds response objects)
  - services/chess/fide_analyzer.py  (builds RuleFinding objects)
"""

from __future__ import annotations

from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, Field


# ── Enumerations ──────────────────────────────────────────────────────────────


class FindingType(str, Enum):
    """
    All FIDE and game-state event types.

    Critical distinction enforced in fide_analyzer.py:
      CLAIMABLE findings → is_automatic = False  (player opportunity)
      AUTOMATIC findings → is_automatic = True   (enforced by rules, game ends)
    """

    # CLAIMABLE draws (FIDE Art. 9.2 / 9.3)
    THREEFOLD_CLAIM_AVAILABLE = "threefold_claim_available"   # board.can_claim_threefold_repetition()
    FIFTY_CLAIM_AVAILABLE = "fifty_claim_available"           # board.can_claim_fifty_moves()

    # AUTOMATIC draws (FIDE Art. 9.6)
    FIVEFOLD_AUTOMATIC = "fivefold_automatic"                 # board.is_fivefold_repetition()
    SEVENTY_FIVE_AUTOMATIC = "seventy_five_automatic"         # board.is_seventyfive_moves()

    # Terminal game states
    CHECKMATE = "checkmate"                                   # board.is_checkmate()
    STALEMATE = "stalemate"                                   # board.is_stalemate()
    INSUFFICIENT_MATERIAL = "insufficient_material"           # board.is_insufficient_material()

    # Analysis issues
    ILLEGAL_MOVE = "illegal_move"
    OCR_UNCERTAIN = "ocr_uncertain"


class GameStatus(str, Enum):
    COMPLETED = "completed"
    PROCESSING = "processing"
    FAILED = "failed"
    NEEDS_REVIEW = "needs_review"


class AnalysisSource(str, Enum):
    """Input source for move analysis."""

    MANUAL = "manual"
    OCR = "ocr"


class ReviewReason(str, Enum):
    """Why a move was flagged for manual review."""

    BELOW_THRESHOLD = "below_threshold"
    LOW_OCR_CONFIDENCE = "low_ocr_confidence"
    AMBIGUOUS_TOP_TWO = "ambiguous_top_two"
    MANUAL_PARSE_FALLBACK = "manual_parse_fallback"
    ILLEGAL_MOVE = "illegal_move"
    LEGACY_NEEDS_REVIEW = "legacy_needs_review"


class DrawDecision(str, Enum):
    """Game-level draw decision summary for arbiter guidance."""

    NONE = "none"
    CLAIMABLE_DRAW = "claimable_draw"
    AUTOMATIC_DRAW = "automatic_draw"


# ── Sub-objects ───────────────────────────────────────────────────────────────


class OCRCandidate(BaseModel):
    """One OCR hypothesis for a move cell, with its confidence score."""

    text: str
    confidence: float = Field(ge=0.0, le=1.0)


class RuleFinding(BaseModel):
    """
    A game-state event detected during FIDE analysis.

    is_automatic=True  → game ends here unconditionally (fivefold, 75-move, checkmate, stalemate)
    is_automatic=False → player opportunity only; arbiter may be notified (threefold, 50-move)
    """

    type: FindingType
    ply_index: int = Field(ge=0)
    description: str
    is_automatic: bool


class GameStats(BaseModel):
    total_moves: int = Field(ge=0)
    auto_resolved: int = Field(ge=0)
    manual_review_required: int = Field(ge=0)
    illegal_moves: int = Field(ge=0)
    ocr_avg_confidence: float = Field(ge=0.0, le=1.0)


class UploadMetadata(BaseModel):
    filename: Optional[str] = None
    uploaded_at: Optional[str] = None


# ── Core per-move object ──────────────────────────────────────────────────────


class MoveAnalysis(BaseModel):
    """
    Full annotation for a single ply (half-move).

    ply_index 0 = White's first move, 1 = Black's first move, etc.
    move_number = chess move number shown on the scoresheet (1-based).
    """

    move_number: int = Field(ge=1)
    ply_index: int = Field(ge=0)
    color: str = Field(pattern="^(white|black)$")

    # OCR provenance
    ocr_raw_text: str
    ocr_candidates: List[OCRCandidate]
    normalized_text: str

    # Validated chess data
    selected_san: Optional[str] = None
    selected_uci: Optional[str] = None
    fen_before: str
    fen_after: str
    is_legal: bool
    needs_manual_review: bool
    confidence: float = Field(ge=0.0, le=1.0)
    review_reasons: List[ReviewReason] = Field(default_factory=list)

    # FIDE alert codes for this specific ply (short strings matching FindingType values)
    fide_alerts: List[str] = Field(default_factory=list)

    # URL to the cropped handwritten cell image (populated in Phase 4+)
    crop_image_url: Optional[str] = None

    # Square of the king in check after this move (e.g. "e8"), else None.
    # Derived by the backend with python-chess — never computed on the frontend.
    check_square: Optional[str] = None


# ── Full game response ────────────────────────────────────────────────────────


class GameAnalysisResponse(BaseModel):
    """
    Complete annotated game record returned by the analysis endpoint.
    Matches the JSON contract defined in the master implementation spec §6.
    """

    game_id: str
    session_id: str
    locale: str = "en"
    status: GameStatus
    upload_metadata: UploadMetadata
    moves: List[MoveAnalysis]
    findings: List[RuleFinding]
    pgn: str
    failure_point_ply: Optional[int] = None
    processing_error: Optional[str] = None
    stats: GameStats
    draw_decision: DrawDecision = DrawDecision.NONE
    draw_reason: Optional[str] = None
    arbiter_must_end: bool = False
    requires_player_claim: bool = False

    model_config = {
        "json_schema_extra": {
            "example": {
                "game_id": "3f7a9b2e-1234-4abc-8def-000000000001",
                "session_id": "anon-uuid-here",
                "locale": "en",
                "status": "completed",
                "upload_metadata": {"filename": None, "uploaded_at": "2024-01-15T10:30:00+00:00"},
                "moves": [
                    {
                        "move_number": 1,
                        "ply_index": 0,
                        "color": "white",
                        "ocr_raw_text": "e4",
                        "ocr_candidates": [{"text": "e4", "confidence": 1.0}],
                        "normalized_text": "e4",
                        "selected_san": "e4",
                        "selected_uci": "e2e4",
                        "fen_before": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                        "fen_after": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
                        "is_legal": True,
                        "needs_manual_review": False,
                        "confidence": 1.0,
                        "review_reasons": [],
                        "fide_alerts": [],
                        "crop_image_url": None,
                    }
                ],
                "findings": [],
                "pgn": '[Event "Arbiter AI Analysis"]\n[Result "*"]\n\n1. e4 *',
                "failure_point_ply": None,
                "processing_error": None,
                "stats": {
                    "total_moves": 1,
                    "auto_resolved": 1,
                    "manual_review_required": 0,
                    "illegal_moves": 0,
                    "ocr_avg_confidence": 1.0,
                },
                "draw_decision": "none",
                "draw_reason": None,
                "arbiter_must_end": False,
                "requires_player_claim": False,
            }
        }
    }


# ── Request schemas ───────────────────────────────────────────────────────────


class AnalyzeMoveListRequest(BaseModel):
    """
    Phase 1 endpoint request: a raw list of SAN move strings.

    In production (Phase 4+), this list comes from the OCR pipeline.
    For this phase, supply pre-written SAN for testing.
    """

    moves: List[str] = Field(
        ...,
        min_length=1,
        description="Ordered list of SAN move strings, White then Black alternating.",
    )
    session_id: Optional[str] = Field(
        default=None,
        description="Anonymous session UUID; auto-generated if omitted.",
    )
    locale: str = Field(
        default="en",
        description=(
            "Piece notation locale for normalization. "
            "Supported: en (default), tr (Turkish), de (German), fr (French), es (Spanish)."
        ),
    )
    analysis_source: AnalysisSource = Field(
        default=AnalysisSource.MANUAL,
        description=(
            "Move input source. Use `manual` for direct SAN entry and `ocr` "
            "for OCR-derived move streams."
        ),
    )

    model_config = {
        "json_schema_extra": {
            "example": {
                "moves": ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6"],
                "session_id": None,
                "locale": "en",
                "analysis_source": "manual",
            }
        }
    }


class ManualCorrectionRequest(BaseModel):
    """Phase 6: submit a manual correction for a specific ply."""

    corrected_san: str = Field(..., description="Corrected SAN move string.")
    locale: str = Field(default="en")
