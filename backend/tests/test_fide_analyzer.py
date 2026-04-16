"""
Tests for FIDEAnalyzer.

Critical invariant: every test that asserts on is_automatic must be correct.
  - Claimable draws (threefold, fifty-move) → is_automatic = False
  - Automatic draws (fivefold, 75-move) → is_automatic = True
  - Terminal states (checkmate, stalemate, insufficient) → is_automatic = True

Run: pytest tests/test_fide_analyzer.py -v
"""

import chess
import pytest

from schemas.analysis import FindingType
from services.chess.fide_analyzer import FIDEAnalyzer


@pytest.fixture
def analyzer() -> FIDEAnalyzer:
    return FIDEAnalyzer()


# ── Helpers ───────────────────────────────────────────────────────────────────


def push_moves(board: chess.Board, sans: list[str]) -> None:
    for san in sans:
        board.push(board.parse_san(san))


# ── Checkmate ─────────────────────────────────────────────────────────────────


def test_scholars_mate_detected(analyzer: FIDEAnalyzer) -> None:
    """Scholar's mate: 1.e4 e5 2.Qh5 Nc6 3.Bc4 Nf6?? 4.Qxf7#"""
    board = chess.Board()
    push_moves(board, ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7"])

    alerts, findings = analyzer.analyze_position(board, ply_index=6)

    assert "checkmate" in alerts
    assert len(findings) == 1
    assert findings[0].type == FindingType.CHECKMATE
    assert findings[0].is_automatic is True
    assert "White wins" in findings[0].description


def test_checkmate_stops_further_checks(analyzer: FIDEAnalyzer) -> None:
    """After checkmate, no other findings should be reported."""
    board = chess.Board()
    push_moves(board, ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7"])

    _, findings = analyzer.analyze_position(board, ply_index=6)

    types = {f.type for f in findings}
    assert types == {FindingType.CHECKMATE}  # only checkmate, nothing else


# ── Stalemate ─────────────────────────────────────────────────────────────────


def test_stalemate_detected(analyzer: FIDEAnalyzer) -> None:
    """
    Classic stalemate position: Black king has no legal moves but is not in check.
    FEN: k7/8/1Q6/8/8/8/8/K7 b - - 0 1  →  after Qb6 it is stalemate.
    We set up White just played Qb6 (Black to move, no legal moves, not in check).
    """
    board = chess.Board("k7/8/1Q6/8/8/8/8/K7 b - - 0 1")
    # Board is already in stalemate state for Black
    assert board.is_stalemate()

    alerts, findings = analyzer.analyze_position(board, ply_index=10)

    assert "stalemate" in alerts
    assert findings[0].type == FindingType.STALEMATE
    assert findings[0].is_automatic is True


# ── Insufficient material ─────────────────────────────────────────────────────


def test_insufficient_material_detected(analyzer: FIDEAnalyzer) -> None:
    """King vs King: insufficient material."""
    board = chess.Board("k7/8/8/8/8/8/8/K7 w - - 0 1")
    assert board.is_insufficient_material()

    alerts, findings = analyzer.analyze_position(board, ply_index=50)

    assert "insufficient_material" in alerts
    assert findings[0].type == FindingType.INSUFFICIENT_MATERIAL
    assert findings[0].is_automatic is True


# ── Claimable draws ───────────────────────────────────────────────────────────


def test_threefold_repetition_claimable(analyzer: FIDEAnalyzer) -> None:
    """
    Knight shuffle produces threefold repetition.

    Sequence: Nf3 Nf6  Ng1 Ng8  Nf3 Nf6  Ng1 Ng8
    After the 8th move, the starting position has appeared 3 times
    (initial + after Ng1/Ng8 + after Ng1/Ng8 again).
    """
    board = chess.Board()
    push_moves(board, ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"])

    assert board.can_claim_threefold_repetition(), (
        "Pre-condition: board should allow threefold claim"
    )

    alerts, findings = analyzer.analyze_position(board, ply_index=7)

    assert "threefold_claim_available" in alerts
    finding = next(f for f in findings if f.type == FindingType.THREEFOLD_CLAIM_AVAILABLE)
    assert finding.is_automatic is False, "Threefold repetition must be CLAIMABLE, not automatic"
    assert "FIDE Art. 9.2" in finding.description


def test_threefold_claim_is_not_automatic(analyzer: FIDEAnalyzer) -> None:
    """Explicitly guard against mis-labeling threefold as automatic."""
    board = chess.Board()
    push_moves(board, ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"])

    _, findings = analyzer.analyze_position(board, ply_index=7)

    for f in findings:
        if f.type == FindingType.THREEFOLD_CLAIM_AVAILABLE:
            assert f.is_automatic is False


# ── Automatic draws ───────────────────────────────────────────────────────────


def test_fivefold_repetition_automatic(analyzer: FIDEAnalyzer) -> None:
    """
    Fivefold repetition: same position appears 5 times → automatic draw.
    Knight shuttle extended: 12 half-moves → position appears 5 times.
    """
    board = chess.Board()
    # Shuttle knights 6 full cycles to reach 5 repetitions of starting position
    push_moves(
        board,
        ["Nf3", "Nf6", "Ng1", "Ng8"] * 3,  # 12 half-moves
    )

    # After 12 half-moves the starting position has appeared 5 times if we
    # include the initial state. Let's verify python-chess agrees:
    if not board.is_fivefold_repetition():
        # Extend until it triggers
        push_moves(board, ["Nf3", "Nf6", "Ng1", "Ng8"])

    assert board.is_fivefold_repetition(), (
        "Pre-condition: should be in fivefold repetition"
    )

    ply = board.ply() - 1
    alerts, findings = analyzer.analyze_position(board, ply_index=ply)

    assert "fivefold_automatic" in alerts
    finding = next(f for f in findings if f.type == FindingType.FIVEFOLD_AUTOMATIC)
    assert finding.is_automatic is True
    assert "FIDE Art. 9.6" in finding.description


# ── is_game_over() ────────────────────────────────────────────────────────────


def test_is_game_over_after_checkmate(analyzer: FIDEAnalyzer) -> None:
    board = chess.Board()
    push_moves(board, ["e4", "e5", "Qh5", "Nc6", "Bc4", "Nf6", "Qxf7"])
    assert analyzer.is_game_over(board) is True


def test_is_game_over_after_stalemate(analyzer: FIDEAnalyzer) -> None:
    board = chess.Board("k7/8/1Q6/8/8/8/8/K7 b - - 0 1")
    assert analyzer.is_game_over(board) is True


def test_is_not_game_over_claimable(analyzer: FIDEAnalyzer) -> None:
    """Claimable draws do NOT count as game over — the game continues."""
    board = chess.Board()
    push_moves(board, ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"])
    assert board.can_claim_threefold_repetition()
    assert analyzer.is_game_over(board) is False


def test_is_not_game_over_mid_game(analyzer: FIDEAnalyzer) -> None:
    board = chess.Board()
    push_moves(board, ["e4", "e5", "Nf3"])
    assert analyzer.is_game_over(board) is False


# ── No double-reporting ───────────────────────────────────────────────────────


def test_no_findings_in_normal_position(analyzer: FIDEAnalyzer) -> None:
    """A normal mid-game position should produce no findings."""
    board = chess.Board()
    push_moves(board, ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"])

    alerts, findings = analyzer.analyze_position(board, ply_index=5)

    assert alerts == []
    assert findings == []
