"""
Tests for ChessService — the full analysis pipeline.

Covers:
  - Valid games (legal moves, correct FEN progression, PGN output)
  - Illegal move detection and early termination
  - FIDE findings propagation
  - Stats computation
  - Normalizer integration (castling, promotion, locale)

Run: pytest tests/test_chess_service.py -v
"""

from __future__ import annotations

import pytest

from schemas.analysis import (
    AnalysisSource,
    DrawDecision,
    FindingType,
    GameStatus,
    ReviewReason,
    RuleFinding,
)
from services.chess.chess_service import ChessService


@pytest.fixture
def service() -> ChessService:
    return ChessService()


# ── Basic correctness ─────────────────────────────────────────────────────────


def test_scholars_mate_full_pipeline(service: ChessService) -> None:
    """Scholar's mate: all 7 moves legal, checkmate finding, status=completed.

    The last move is entered as "Qxf7" (without checkmate "#" — OCR rarely
    captures annotation symbols).  The matcher strips "#" before comparing so
    "Qxf7" still achieves an exact Levenshtein match against "Qxf7#".
    """
    result = service.analyze_game(["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7"])

    assert result.status == GameStatus.COMPLETED
    assert len(result.moves) == 7
    assert all(m.is_legal for m in result.moves)
    assert result.failure_point_ply is None

    checkmate_findings = [f for f in result.findings if f.type == FindingType.CHECKMATE]
    assert len(checkmate_findings) == 1
    assert checkmate_findings[0].ply_index == 6
    assert checkmate_findings[0].is_automatic is True


def test_ruy_lopez_opening(service: ChessService) -> None:
    """8 moves of Ruy Lopez — all legal, no FIDE events."""
    moves = ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6"]
    result = service.analyze_game(moves)

    assert result.status == GameStatus.COMPLETED
    assert len(result.moves) == 8
    assert result.findings == []
    assert result.stats.illegal_moves == 0
    assert result.stats.manual_review_required == 0


def test_empty_move_list_raises(service: ChessService) -> None:
    """An empty list produces an empty but valid response."""
    result = service.analyze_game([])

    assert len(result.moves) == 0
    assert result.stats.total_moves == 0
    assert result.failure_point_ply is None


# ── FEN progression ───────────────────────────────────────────────────────────


def test_fen_before_first_move_is_start_position(service: ChessService) -> None:
    result = service.analyze_game(["e4", "e5"])

    starting = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    assert result.moves[0].fen_before == starting


def test_fen_after_chains_to_fen_before(service: ChessService) -> None:
    """fen_after of move N must equal fen_before of move N+1."""
    result = service.analyze_game(["e4", "e5", "Nf3", "Nc6"])

    for i in range(len(result.moves) - 1):
        assert result.moves[i].fen_after == result.moves[i + 1].fen_before


def test_fen_after_differs_from_fen_before(service: ChessService) -> None:
    result = service.analyze_game(["e4"])
    assert result.moves[0].fen_before != result.moves[0].fen_after


# ── UCI output ────────────────────────────────────────────────────────────────


def test_uci_populated_for_legal_moves(service: ChessService) -> None:
    result = service.analyze_game(["e4", "e5"])
    assert result.moves[0].selected_uci == "e2e4"
    assert result.moves[1].selected_uci == "e7e5"


# ── PGN generation ────────────────────────────────────────────────────────────


def test_pgn_contains_moves(service: ChessService) -> None:
    result = service.analyze_game(["e4", "e5", "Nf3"])
    assert "e4" in result.pgn
    assert "e5" in result.pgn
    assert "Nf3" in result.pgn


def test_pgn_result_after_checkmate(service: ChessService) -> None:
    result = service.analyze_game(["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7"])
    assert "1-0" in result.pgn  # White wins by Scholar's mate


# ── Fuzzy-match / review handling (Phase 5 semantics) ────────────────────────
#
# Phase 5 never strictly rejects a move as "illegal" unless its matcher score
# falls below MIN_MATCH_SCORE.  When OCR text doesn't match any legal move
# well, the best candidate is still returned — but flagged needs_manual_review.
#
# Inputs that fall below MIN_MATCH_SCORE (e.g. zero OCR confidence + garbage
# text) produce is_legal=False and stop the game.


def test_ambiguous_move_sets_needs_review(service: ChessService) -> None:
    """'e5' is not a legal White move after 1.e4 e5, but it fuzzy-matches some
    legal move.  The result is flagged for review — the game does NOT stop."""
    result = service.analyze_game(["e4", "e5", "e5"])

    assert result.status == GameStatus.NEEDS_REVIEW
    third = result.moves[2]
    assert third.is_legal is True          # fuzzy-matched to a legal move
    assert third.needs_manual_review is True
    assert third.selected_san is not None  # best candidate was chosen


def test_all_moves_processed_when_fuzzy_match_succeeds(service: ChessService) -> None:
    """Phase 5 processes all moves even when OCR text doesn't match exactly."""
    result = service.analyze_game(["e4", "e5", "e5", "Nf3", "Nc6"])
    assert len(result.moves) == 5


def test_unreadable_move_stops_game(service: ChessService) -> None:
    """When OCR confidence is 0 and text is garbage, score < MIN_MATCH_SCORE
    → is_legal=False, game stops, failure_point_ply is set."""
    result = service.analyze_game(
        ["e4", "e5", "zzz"],
        ocr_confidences=[1.0, 1.0, 0.0],
    )
    assert result.failure_point_ply == 2
    assert result.moves[2].is_legal is False
    assert result.moves[2].needs_manual_review is True
    assert result.moves[2].selected_san is None
    assert result.moves[2].selected_uci is None

    # Board must not advance on a failed match
    illegal = result.moves[2]
    assert illegal.fen_before == illegal.fen_after

    # An ILLEGAL_MOVE finding must be recorded
    illegal_findings = [f for f in result.findings if f.type == FindingType.ILLEGAL_MOVE]
    assert len(illegal_findings) == 1
    assert illegal_findings[0].ply_index == 2


def test_completely_bogus_move(service: ChessService) -> None:
    """'Zz9' fuzzy-matches some legal move but is flagged for review."""
    result = service.analyze_game(["e4", "Zz9"])
    assert result.status == GameStatus.NEEDS_REVIEW
    assert result.moves[1].needs_manual_review is True


# ── Stats ─────────────────────────────────────────────────────────────────────


def test_stats_all_legal(service: ChessService) -> None:
    result = service.analyze_game(["e4", "e5", "Nf3", "Nc6"])
    s = result.stats
    assert s.total_moves == 4
    assert s.illegal_moves == 0
    assert s.manual_review_required == 0
    assert s.auto_resolved == 4
    # ocr_avg_confidence reflects the matcher score (0.9 for exact match
    # at default ocr_confidence=1.0: score = 0.5*1.0 + 0.4*1.0 = 0.90)
    assert s.ocr_avg_confidence == pytest.approx(0.90)


def test_stats_with_unreadable_move(service: ChessService) -> None:
    """When a move falls below MIN_MATCH_SCORE it is counted as illegal."""
    result = service.analyze_game(
        ["e4", "e5", "zzz"],
        ocr_confidences=[1.0, 1.0, 0.0],
    )
    s = result.stats
    assert s.total_moves == 3
    assert s.illegal_moves == 1
    assert s.manual_review_required == 1
    assert s.auto_resolved == 2


# ── Normalizer integration ────────────────────────────────────────────────────


def test_castling_zero_zero_normalized(service: ChessService) -> None:
    """0-0 must be accepted as a valid kingside castling notation."""
    moves = ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6",
             "O-O", "Be7"]  # White castles kingside
    result = service.analyze_game(moves)
    assert result.moves[8].is_legal is True
    assert result.moves[8].selected_san == "O-O"


def test_castling_digit_zero_accepted(service: ChessService) -> None:
    """0-0 (digit zeros, common OCR output) must normalize to O-O."""
    moves = ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6",
             "0-0", "Be7"]   # 0-0 with digit zero
    result = service.analyze_game(moves)
    assert result.moves[8].is_legal is True
    assert result.moves[8].normalized_text == "O-O"


def test_promotion_without_equals_sign(service: ChessService) -> None:
    """e8Q must normalize to e8=Q and be accepted as pawn promotion."""
    # Set up a position where a pawn is about to promote
    # FEN: white pawn on e7, black king far away, white king on a1
    board_fen = "8/4P3/8/8/8/8/8/K6k w - - 0 1"
    from services.chess.normalizer import MoveNormalizer
    normalizer = MoveNormalizer()
    assert normalizer.normalize("e8Q") == "e8=Q"
    assert normalizer.normalize("e8(Q)") == "e8=Q"
    assert normalizer.normalize("e8/Q") == "e8=Q"


def test_move_numbers_stripped(service: ChessService) -> None:
    """Move numbers like '1. e4' should still parse as 'e4'."""
    result = service.analyze_game(["1. e4", "1... e5", "2. Nf3"])
    assert result.moves[0].is_legal is True
    assert result.moves[0].normalized_text == "e4"
    assert result.moves[1].normalized_text == "e5"
    assert result.moves[2].normalized_text == "Nf3"


# ── Session / ID fields ───────────────────────────────────────────────────────


def test_game_id_and_session_id_populated(service: ChessService) -> None:
    result = service.analyze_game(["e4"], session_id="test-session-123")
    assert result.game_id  # non-empty
    assert result.session_id == "test-session-123"


def test_session_id_auto_generated_when_none(service: ChessService) -> None:
    result = service.analyze_game(["e4"])
    assert result.session_id  # non-empty, auto-generated UUID


# ── Ruy Lopez regression (bug: O-O not recognised) ───────────────────────────
#
# Reported: manual entry of a 16-move Ruy Lopez returned 18 moves with
# Ng1/Nb8 knight-shuttle repetitions.  Root cause: mobile keyboards can add
# spaces around hyphens, splitting "O-O" into the three tokens "O", "-", "O".
# The "-" token fuzzy-matched a random legal move, corrupting the board state.
# Fixes applied:
#   1. manual_entry_screen.dart: autocorrect=false, enableSuggestions=false
#   2. _parseMoves(): pre-normalise "O - O" → "O-O" before tokenising
#   3. normalizer.py: map all Unicode hyphen variants to ASCII "-"


RUY_LOPEZ_16 = [
    "e4", "e5", "Nf3", "Nc6", "Bb5", "a6",
    "Ba4", "Nf6", "O-O", "Be7", "Re1", "b5",
    "Bb3", "d6", "c3", "O-O",
]


def test_ruy_lopez_16_moves_all_legal(service: ChessService) -> None:
    """All 16 Ruy Lopez moves must be legal and produce zero findings."""
    result = service.analyze_game(RUY_LOPEZ_16)

    assert len(result.moves) == 16, (
        f"Expected 16 moves, got {len(result.moves)}. "
        "If castling was split into tokens, extra moves appear here."
    )
    illegal = [m for m in result.moves if not m.is_legal]
    assert illegal == [], f"Illegal moves: {[(m.ply_index, m.ocr_raw_text) for m in illegal]}"
    assert result.findings == [], f"Unexpected findings: {result.findings}"
    assert result.failure_point_ply is None


def test_ruy_lopez_both_castling_moves_recognized(service: ChessService) -> None:
    """O-O at ply 8 (White) and ply 15 (Black) must both select 'O-O'."""
    result = service.analyze_game(RUY_LOPEZ_16)

    white_castle = result.moves[8]
    black_castle = result.moves[15]

    assert white_castle.selected_san == "O-O", (
        f"White castling not recognized: selected {white_castle.selected_san!r}"
    )
    assert black_castle.selected_san == "O-O", (
        f"Black castling not recognized: selected {black_castle.selected_san!r}"
    )


def test_castling_unicode_hyphens_accepted(service: ChessService) -> None:
    """Castling with Unicode dash variants must all resolve to O-O.

    Mobile keyboards (especially iOS Smart Punctuation) can replace ASCII
    hyphens with typographic dashes.  The normalizer must handle all of them.
    """
    from services.chess.normalizer import MoveNormalizer
    norm = MoveNormalizer()

    unicode_hyphens = [
        "\u2010",   # ‐ hyphen (typographic)
        "\u2011",   # ‑ non-breaking hyphen
        "\u2012",   # ‒ figure dash
        "\u2013",   # – en dash
        "\u2014",   # — em dash
        "\u2015",   # ― horizontal bar
        "\u2212",   # − minus sign
    ]
    for dash in unicode_hyphens:
        castling_input = f"O{dash}O"
        result = norm.normalize(castling_input, "en")
        assert result == "O-O", (
            f"O{dash!r}O (U+{ord(dash):04X}) normalized to {result!r}, expected 'O-O'"
        )


def test_ruy_lopez_digit_zero_castling(service: ChessService) -> None:
    """0-0 (digit zeros, common OCR output) must work in a full 16-move game."""
    moves_with_zeros = list(RUY_LOPEZ_16)
    moves_with_zeros[8] = "0-0"
    moves_with_zeros[15] = "0-0"

    result = service.analyze_game(moves_with_zeros)

    assert len(result.moves) == 16
    assert result.moves[8].selected_san == "O-O"
    assert result.moves[15].selected_san == "O-O"
    assert all(m.is_legal for m in result.moves)


# ── Manual source behavior (hybrid parse) ───────────────────────────────────


def test_manual_source_exact_parse_skips_fuzzy_review(service: ChessService) -> None:
    """Manual mode should accept a directly legal SAN without fuzzy review."""
    result = service.analyze_game(
        ["e4", "e5"],
        analysis_source=AnalysisSource.MANUAL,
    )

    assert result.moves[0].selected_san == "e4"
    assert result.moves[0].needs_manual_review is False
    assert result.moves[0].confidence == pytest.approx(1.0)
    assert result.moves[0].review_reasons == []


def test_manual_source_fallback_sets_reason(service: ChessService) -> None:
    """When strict parse fails in manual mode, fallback must be explicit."""
    result = service.analyze_game(
        ["e4", "e5", "e5"],
        analysis_source=AnalysisSource.MANUAL,
    )

    third = result.moves[2]
    assert third.needs_manual_review is True
    assert ReviewReason.MANUAL_PARSE_FALLBACK in third.review_reasons


def test_illegal_move_sets_illegal_reason(service: ChessService) -> None:
    """Illegal/no-match move should expose ILLEGAL_MOVE review reason."""
    result = service.analyze_game(
        ["e4", "e5", "zzz"],
        ocr_confidences=[1.0, 1.0, 0.0],
    )

    illegal = result.moves[2]
    assert illegal.is_legal is False
    assert illegal.needs_manual_review is True
    assert illegal.review_reasons == [ReviewReason.ILLEGAL_MOVE]


# ── Draw-decision summary ────────────────────────────────────────────────────


def test_claimable_draw_summary_in_response(service: ChessService) -> None:
    """Threefold claim availability should be exposed as claimable draw."""
    result = service.analyze_game(
        ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"],
    )

    assert result.draw_decision == DrawDecision.CLAIMABLE_DRAW
    assert result.requires_player_claim is True
    assert result.arbiter_must_end is False
    assert result.draw_reason in {
        FindingType.THREEFOLD_CLAIM_AVAILABLE.value,
        FindingType.FIFTY_CLAIM_AVAILABLE.value,
    }


def test_compute_draw_summary_automatic_priority(service: ChessService) -> None:
    """Automatic draw signal should take precedence over claimable signals."""
    findings = [
        RuleFinding(
            type=FindingType.THREEFOLD_CLAIM_AVAILABLE,
            ply_index=10,
            description="claimable",
            is_automatic=False,
        ),
        RuleFinding(
            type=FindingType.FIVEFOLD_AUTOMATIC,
            ply_index=20,
            description="automatic",
            is_automatic=True,
        ),
    ]

    draw_decision, draw_reason, arbiter_must_end, requires_player_claim = (
        service._compute_draw_summary(findings)
    )

    assert draw_decision == DrawDecision.AUTOMATIC_DRAW
    assert draw_reason == FindingType.FIVEFOLD_AUTOMATIC.value
    assert arbiter_must_end is True
    assert requires_player_claim is False


# ── Check-square derivation (board overlay support) ────────────────────────────


def test_check_square_set_on_checking_move(service: ChessService) -> None:
    """A move that gives check exposes the checked king's square.

    1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6?? 4. Qxf7# — the final move is checkmate,
    which is also a check, so the black king on e8 must be reported.
    """
    result = service.analyze_game(["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7"])

    final = result.moves[-1]
    assert final.is_legal
    assert final.check_square == "e8"


def test_check_square_none_on_quiet_move(service: ChessService) -> None:
    """Quiet opening moves give no check, so check_square stays None."""
    result = service.analyze_game(["e4", "e5", "Nf3", "Nc6"])

    assert all(m.check_square is None for m in result.moves)


def test_check_square_helpers() -> None:
    """The python-chess helpers resolve the checked king from a board/FEN."""
    from services.chess.chess_service import (
        check_square_from_board,
        check_square_from_fen,
    )
    import chess

    board = chess.Board()
    assert check_square_from_board(board) is None  # start position, no check

    # Black king in check from a white queen on e7 (scholar's-mate-like).
    checked_fen = "rnbqkbnr/ppppQppp/8/8/8/8/PPPP1PPP/RNB1KBNR b KQkq - 0 1"
    assert check_square_from_fen(checked_fen) == "e8"

    assert check_square_from_fen("not a real fen") is None
