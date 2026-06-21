"""
Chess game analysis service — the backend's authoritative chess logic layer.

Responsibilities:
  - Accept a list of raw move strings (SAN, potentially OCR-dirty)
  - Normalize each move via MoveNormalizer
  - Validate each move against the actual board state (python-chess)
  - Run FIDE analysis after every move push (FIDEAnalyzer)
  - Return a fully annotated GameAnalysisResponse

This service is called by:
  - api/routes/games.py (Phase 1: direct move list)
  - workers/processing_tasks.py (Phase 4+: after OCR pipeline)

RULE: No chess logic lives anywhere outside this module and fide_analyzer.py.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import List, Optional

import chess
import chess.pgn

from schemas.analysis import (
    AnalysisSource,
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
from services.chess.candidate_matcher import CandidateMatcher, MIN_MATCH_SCORE
from services.chess.fide_analyzer import FIDEAnalyzer
from services.chess.normalizer import MoveNormalizer


def check_square_from_board(board: chess.Board) -> Optional[str]:
    """Square name of the king currently in check, or None.

    The side to move (``board.turn``) is the one whose king may be in check
    after the previous move was pushed. Lives here so all python-chess reasoning
    stays inside the chess module (see RULE above).
    """
    if not board.is_check():
        return None
    king_sq = board.king(board.turn)
    return chess.square_name(king_sq) if king_sq is not None else None


def check_square_from_fen(fen: str) -> Optional[str]:
    """Derive the checked-king square from a stored FEN. Returns None on bad FEN."""
    try:
        return check_square_from_board(chess.Board(fen))
    except ValueError:
        return None


class ChessService:
    """
    Stateless chess game analysis.  A single instance is safe to share across
    requests (no mutable state between calls).
    """

    def __init__(self) -> None:
        self._fide = FIDEAnalyzer()
        self._normalizer = MoveNormalizer()
        self._matcher = CandidateMatcher()

    # ── Public API ────────────────────────────────────────────────────────────

    def analyze_game(
        self,
        raw_moves: List[str],
        session_id: Optional[str] = None,
        locale: str = "en",
        game_id: Optional[str] = None,
        upload_metadata: Optional[UploadMetadata] = None,
        ocr_confidences: Optional[List[float]] = None,
        analysis_source: AnalysisSource = AnalysisSource.OCR,
    ) -> GameAnalysisResponse:
        """
        Core analysis pipeline.

        For each ply:
          1. Normalize OCR text
          2. Parse + validate against board (exact match in Phase 1)
          3. Push move and record FEN before/after
          4. Run FIDE analysis on the resulting position
          5. Stop processing on illegal move or automatic game-over

        Args:
            raw_moves:        Raw move strings in arrival order (White, Black, White …)
            session_id:       Anonymous session UUID; auto-generated if None
            locale:           Piece notation locale code (en, tr, de, fr, es)
            game_id:          Pre-assigned game UUID; auto-generated if None
            upload_metadata:  Populated by Phase 2+ upload flow; None here
            ocr_confidences:  Per-move OCR confidence scores [0,1].  If None,
                              all moves are treated as confidence 1.0 (Phase 1 API).
            analysis_source:  `manual` runs strict SAN parse first, then fuzzy
                              matcher as a fallback. `ocr` always uses matcher.

        Returns:
            Fully annotated GameAnalysisResponse
        """
        game_id = game_id or str(uuid.uuid4())
        session_id = session_id or str(uuid.uuid4())

        board = chess.Board()
        analyzed_moves: List[MoveAnalysis] = []
        all_findings: List[RuleFinding] = []
        failure_point_ply: Optional[int] = None
        game_ended = False
        # Tracks which FindingTypes have already been emitted for this game.
        # Passed to FIDEAnalyzer so it can deduplicate persistent conditions
        # (e.g. threefold repetition remaining claimable for many consecutive plies).
        seen_finding_types: set[FindingType] = set()

        for ply_index, raw_san in enumerate(raw_moves):
            if game_ended:
                break

            color = "white" if ply_index % 2 == 0 else "black"
            move_number = (ply_index // 2) + 1
            fen_before = board.fen()

            # Per-ply OCR confidence (1.0 when called from Phase 1 API)
            ocr_conf = (
                ocr_confidences[ply_index]
                if ocr_confidences and ply_index < len(ocr_confidences)
                else 1.0
            )

            # Step 1 — Normalize
            normalized = self._normalizer.normalize(raw_san, locale)

            # Step 2 — Resolve move candidate based on analysis source.
            rankings = []
            best = None
            selected_move: Optional[chess.Move] = None
            selected_san: Optional[str] = None
            selected_confidence = 0.0
            selected_needs_review = False
            review_reasons: List[ReviewReason] = []
            used_manual_fallback = False

            if analysis_source == AnalysisSource.MANUAL:
                # Manual entry: try exact/legal SAN first; fallback to matcher
                # only when strict parsing fails.
                parsed_move, _ = self._parse_move(board, normalized)
                if parsed_move is not None:
                    selected_move = parsed_move
                    selected_san = board.san(parsed_move)
                    selected_confidence = 1.0
                else:
                    used_manual_fallback = True
                    rankings = self._matcher.rank_candidates(normalized, board, ocr_conf)
                    best = rankings[0] if rankings else None
            else:
                rankings = self._matcher.rank_candidates(normalized, board, ocr_conf)
                best = rankings[0] if rankings else None

            no_match = selected_move is None and (best is None or best.score < MIN_MATCH_SCORE)

            if no_match:
                # No legal move is similar enough — record as illegal and stop.
                no_match_reasons: List[ReviewReason] = [ReviewReason.ILLEGAL_MOVE]
                if used_manual_fallback:
                    no_match_reasons.append(ReviewReason.MANUAL_PARSE_FALLBACK)

                if rankings:
                    no_match_candidates = [
                        OCRCandidate(text=r.san, confidence=round(r.score, 4))
                        for r in rankings[:5]
                    ]
                else:
                    no_match_candidates = [OCRCandidate(text=normalized, confidence=0.0)]

                all_findings.append(RuleFinding(
                    type=FindingType.ILLEGAL_MOVE,
                    ply_index=ply_index,
                    description=(
                        f"No legal move matches '{raw_san}' "
                        f"(normalized: '{normalized}') "
                        f"for {color} at move {move_number}."
                    ),
                    is_automatic=True,
                ))
                failure_point_ply = ply_index
                analyzed_moves.append(MoveAnalysis(
                    move_number=move_number,
                    ply_index=ply_index,
                    color=color,
                    ocr_raw_text=raw_san,
                    ocr_candidates=no_match_candidates,
                    normalized_text=normalized,
                    selected_san=None,
                    selected_uci=None,
                    fen_before=fen_before,
                    fen_after=fen_before,   # board did NOT advance
                    is_legal=False,
                    needs_manual_review=True,
                    confidence=0.0,
                    review_reasons=no_match_reasons,
                    fide_alerts=["illegal_move"],
                    crop_image_url=None,
                ))
                game_ended = True
                continue

            if selected_move is None:
                # Fuzzy matcher path
                selected_move = board.parse_san(best.san)  # type: ignore[union-attr]
                selected_san = board.san(selected_move)
                selected_confidence = round(best.score, 4)  # type: ignore[union-attr]
                selected_needs_review = bool(best.needs_review)  # type: ignore[union-attr]
                review_reasons = list(best.review_reasons)  # type: ignore[union-attr]
                if used_manual_fallback:
                    selected_needs_review = True
                    if ReviewReason.MANUAL_PARSE_FALLBACK not in review_reasons:
                        review_reasons.append(ReviewReason.MANUAL_PARSE_FALLBACK)
            else:
                # Strict manual parse path
                selected_san = selected_san or board.san(selected_move)
                selected_confidence = 1.0
                selected_needs_review = False
                review_reasons = []

            if selected_needs_review and not review_reasons:
                review_reasons = [ReviewReason.LEGACY_NEEDS_REVIEW]

            # Step 3 — push validated move
            canonical_san = selected_san or board.san(selected_move)
            board.push(selected_move)
            fen_after = board.fen()
            check_square = check_square_from_board(board)

            # Step 4 — FIDE analysis on the resulting position
            fide_alerts, move_findings = self._fide.analyze_position(
                board, ply_index, seen_finding_types
            )
            all_findings.extend(move_findings)

            # Build candidate list for UI transparency.
            if rankings:
                ocr_candidates = [
                    OCRCandidate(text=r.san, confidence=round(r.score, 4))
                    for r in rankings[:5]
                ]
            else:
                ocr_candidates = [
                    OCRCandidate(text=canonical_san, confidence=1.0)
                ]

            analyzed_moves.append(MoveAnalysis(
                move_number=move_number,
                ply_index=ply_index,
                color=color,
                ocr_raw_text=raw_san,
                ocr_candidates=ocr_candidates,
                normalized_text=normalized,
                selected_san=canonical_san,
                selected_uci=selected_move.uci(),
                fen_before=fen_before,
                fen_after=fen_after,
                is_legal=True,
                needs_manual_review=selected_needs_review,
                confidence=selected_confidence,
                review_reasons=review_reasons,
                fide_alerts=fide_alerts,
                crop_image_url=None,
                check_square=check_square,
            ))

            # Step 5 — Stop if the game is unconditionally over
            if self._fide.is_game_over(board):
                game_ended = True

        # ── Build response ────────────────────────────────────────────────────

        legal_sans = [
            m.selected_san
            for m in analyzed_moves
            if m.is_legal and m.selected_san is not None
        ]
        pgn = self._generate_pgn(legal_sans, board)

        status = self._determine_status(analyzed_moves, failure_point_ply)
        draw_decision, draw_reason, arbiter_must_end, requires_player_claim = (
            self._compute_draw_summary(all_findings)
        )

        return GameAnalysisResponse(
            game_id=game_id,
            session_id=session_id,
            locale=locale,
            status=status,
            upload_metadata=upload_metadata or UploadMetadata(
                filename=None,
                uploaded_at=datetime.now(timezone.utc).isoformat(),
            ),
            moves=analyzed_moves,
            findings=all_findings,
            pgn=pgn,
            failure_point_ply=failure_point_ply,
            stats=self._compute_stats(analyzed_moves),
            draw_decision=draw_decision,
            draw_reason=draw_reason,
            arbiter_must_end=arbiter_must_end,
            requires_player_claim=requires_player_claim,
        )

    def get_legal_sans(self, fen: str) -> List[str]:
        """Return all legal SAN moves for a given FEN position."""
        board = chess.Board(fen)
        return [board.san(m) for m in board.legal_moves]

    # ── Private helpers ───────────────────────────────────────────────────────

    def _parse_move(
        self, board: chess.Board, san: str
    ) -> tuple[Optional[chess.Move], Optional[str]]:
        """
        Attempt to parse a SAN string in the context of the current board.

        Returns:
            (move, None)          on success
            (None, error_message) on failure
        """
        try:
            move = board.parse_san(san)
            # parse_san raises for illegal moves, but double-check
            if move not in board.legal_moves:
                return None, f"Move {san!r} is not in the legal move set"
            return move, None
        except chess.InvalidMoveError as e:
            return None, f"InvalidMoveError: {e}"
        except chess.AmbiguousMoveError as e:
            return None, f"AmbiguousMoveError: {e}"
        except chess.IllegalMoveError as e:
            return None, f"IllegalMoveError: {e}"
        except ValueError as e:
            return None, f"ValueError: {e}"

    def _generate_pgn(self, legal_sans: List[str], final_board: chess.Board) -> str:
        """
        Build a PGN string from a list of canonical SAN moves.

        Uses python-chess pgn module for correct formatting.
        The result header reflects the actual game outcome.
        """
        game = chess.pgn.Game()
        game.headers["Event"] = "Arbiter AI Analysis"
        game.headers["Result"] = final_board.result()

        node = game
        board = chess.Board()
        for san in legal_sans:
            try:
                move = board.parse_san(san)
                node = node.add_variation(move)
                board.push(move)
            except Exception:
                # Stop PGN at first error; the caller has already recorded the issue
                break

        exporter = chess.pgn.StringExporter(
            headers=True, variations=False, comments=False
        )
        return game.accept(exporter)

    def _determine_status(
        self,
        moves: List[MoveAnalysis],
        failure_point_ply: Optional[int],
    ) -> GameStatus:
        if failure_point_ply is not None:
            return GameStatus.NEEDS_REVIEW
        if any(m.needs_manual_review for m in moves):
            return GameStatus.NEEDS_REVIEW
        return GameStatus.COMPLETED

    def _compute_stats(self, moves: List[MoveAnalysis]) -> GameStats:
        total = len(moves)
        review_required = sum(1 for m in moves if m.needs_manual_review)
        illegal = sum(1 for m in moves if not m.is_legal)
        auto_resolved = total - review_required
        avg_conf = (
            sum(m.confidence for m in moves) / total if total > 0 else 0.0
        )
        return GameStats(
            total_moves=total,
            auto_resolved=auto_resolved,
            manual_review_required=review_required,
            illegal_moves=illegal,
            ocr_avg_confidence=round(avg_conf, 4),
        )

    def _compute_draw_summary(
        self,
        findings: List[RuleFinding],
    ) -> tuple[DrawDecision, Optional[str], bool, bool]:
        """
        Build a game-level draw decision summary for arbiter-facing UI.

        Priority:
          1) Automatic draw findings (must end game)
          2) Claimable draw findings (game continues; claim required)
          3) No draw signal
        """
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
