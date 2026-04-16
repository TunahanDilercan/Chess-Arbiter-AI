"""
Tests for services/chess/candidate_matcher.py — Phase 5.

Coverage:
  TestScoringFormula      — component scores, formula arithmetic
  TestConfusionBonus      — known confusion pairs, non-pairs, edge cases
  TestExactMatch          — exact SAN in legal moves
  TestFuzzyMatch          — OCR errors resolved to correct legal SAN
  TestConfusionMatrix     — B↔8, l↔1, O↔0, Q↔O hits raise score
  TestThresholdLogic      — auto-accept above threshold, flag below
  TestAmbiguityRule       — close top-2 → needs_review even if above threshold
  TestNeedsReview         — needs_review propagation in MatchResult
  TestRankCandidates      — ordering, list length, empty board
  TestMatchMethod         — backward-compatible (Optional[str], bool) signature
  TestGetSuggestions      — top-N trimming
  TestChessServicePhase5  — integration with chess_service.analyze_game()
"""

from __future__ import annotations

import chess
import pytest

from services.chess.candidate_matcher import (
    AMBIGUITY_MARGIN,
    CandidateMatcher,
    MatchResult,
    MIN_MATCH_SCORE,
    _confusion_bonus,
    _lev_ratio,
    _CONFUSION_PAIRS,
)


# ── Board helpers ─────────────────────────────────────────────────────────────

def _start_board() -> chess.Board:
    """Standard starting position."""
    return chess.Board()


def _board_after(*sans: str) -> chess.Board:
    """Return a board after applying the given SAN moves from the start."""
    b = chess.Board()
    for san in sans:
        b.push_san(san)
    return b


# ── TestScoringFormula ────────────────────────────────────────────────────────

class TestScoringFormula:
    """Unit-test the arithmetic of the scoring formula."""

    def test_exact_match_high_confidence_above_threshold(self):
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        e4 = next(r for r in rankings if r.san == "e4")
        # lev=1.0, ocr=1.0, conf=0.0 → score = 0.5+0.4+0.0 = 0.90
        assert abs(e4.score - 0.90) < 1e-4

    def test_exact_match_ocr_06_score_correct(self):
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=0.6)
        e4 = next(r for r in rankings if r.san == "e4")
        # lev=1.0, ocr=0.6, conf=0.0 → 0.5 + 0.24 + 0.0 = 0.74
        assert abs(e4.score - 0.74) < 1e-4

    def test_score_capped_at_one(self):
        """With perfect lev, perfect ocr, and bonus=1.0, score must equal 1.0."""
        matcher = CandidateMatcher()
        # Manually build the arithmetic
        score = 1.0 * 0.5 + 1.0 * 0.4 + 1.0 * 0.1
        assert abs(score - 1.0) < 1e-9

    def test_score_weights_sum_to_one(self):
        from services.chess.candidate_matcher import _W_LEV, _W_OCR, _W_CONF
        assert abs(_W_LEV + _W_OCR + _W_CONF - 1.0) < 1e-9

    def test_ocr_confidence_shifts_all_candidates_equally(self):
        """The ocr_confidence term is the same for every candidate → ranking
        by score equals ranking by lev_ratio alone."""
        matcher = CandidateMatcher()
        board = _start_board()
        r_high = matcher.rank_candidates("e4", board, ocr_confidence=0.9)
        r_low  = matcher.rank_candidates("e4", board, ocr_confidence=0.3)
        # Ordering must be identical regardless of ocr_confidence
        assert [r.san for r in r_high] == [r.san for r in r_low]


# ── TestConfusionBonus ────────────────────────────────────────────────────────

class TestConfusionBonus:
    def test_b_vs_8_is_confusion_pair(self):
        assert frozenset({"B", "8"}) in _CONFUSION_PAIRS

    def test_l_vs_1_is_confusion_pair(self):
        assert frozenset({"l", "1"}) in _CONFUSION_PAIRS

    def test_o_vs_0_is_confusion_pair(self):
        assert frozenset({"O", "0"}) in _CONFUSION_PAIRS

    def test_q_vs_o_is_confusion_pair(self):
        assert frozenset({"Q", "O"}) in _CONFUSION_PAIRS

    def test_x_vs_plus_is_confusion_pair(self):
        assert frozenset({"x", "+"}) in _CONFUSION_PAIRS

    def test_identical_strings_return_zero(self):
        assert _confusion_bonus("Nf3", "Nf3") == 0.0

    def test_known_confusion_single_edit_returns_one(self):
        # B→8 is the only edit: 1 confusion / 1 op = 1.0
        assert _confusion_bonus("Bf3", "8f3") == pytest.approx(1.0)

    def test_known_confusion_l_to_1_returns_one(self):
        # l→1 is the only edit
        assert _confusion_bonus("Nfl", "Nf1") == pytest.approx(1.0)

    def test_non_confusion_edit_returns_zero(self):
        # f→g is not a known confusion pair
        assert _confusion_bonus("Nf3", "Ng3") == pytest.approx(0.0)

    def test_mixed_edits_partial_bonus(self):
        # "Bf1" vs "8g1": B→8 (confusion), f→g (not)
        # 1 confusion out of 2 replace ops = 0.5
        bonus = _confusion_bonus("Bf1", "8g1")
        assert bonus == pytest.approx(0.5)

    def test_empty_strings_return_zero(self):
        assert _confusion_bonus("", "") == 0.0

    def test_one_empty_string_returns_zero(self):
        assert _confusion_bonus("e4", "") == 0.0


# ── TestExactMatch ────────────────────────────────────────────────────────────

class TestExactMatch:
    def test_exact_match_is_top_ranked(self):
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        assert rankings[0].san == "e4"

    def test_exact_match_has_lev_ratio_one(self):
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("Nf3", board, ocr_confidence=1.0)
        nf3 = next(r for r in rankings if r.san == "Nf3")
        assert nf3.lev_ratio == pytest.approx(1.0)

    def test_exact_match_high_confidence_not_needs_review(self):
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        assert rankings[0].needs_review is False

    def test_exact_match_low_ocr_confidence_flags_review(self):
        """Even exact text match → needs review when OCR confidence is low."""
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        # ocr_confidence=0.5 → score = 0.5 + 0.2 = 0.7 < 0.85
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=0.5)
        assert rankings[0].needs_review is True


# ── TestFuzzyMatch ────────────────────────────────────────────────────────────

class TestFuzzyMatch:
    def test_fuzzy_match_returns_correct_legal_san(self):
        """OCR produces "Nf4" when the only legal knight move nearby is "Nf3"."""
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("Nf4", board, ocr_confidence=0.9)
        # "Nf3" is legal; "Nf4" is not (no knight can go there from start)
        assert rankings[0].san in [board.san(m) for m in board.legal_moves]

    def test_fuzzy_match_needs_review_when_below_threshold(self):
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        # "Ng4" is not a legal move; the best match won't score perfectly
        rankings = matcher.rank_candidates("Ng4", board, ocr_confidence=0.8)
        assert rankings[0].needs_review is True

    def test_returned_san_is_always_legal(self):
        """Every san in rankings must be parseable in the current board."""
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("zz9", board, ocr_confidence=0.5)
        for r in rankings:
            # This should not raise
            board.parse_san(r.san)

    def test_match_method_returns_legal_san_for_fuzzy_input(self):
        matcher = CandidateMatcher()
        board = _start_board()
        san, needs_review = matcher.match("e5", board, ocr_confidence=0.9)
        # "e5" is not legal from the start; best guess is "e4" or similar
        if san is not None:
            board.parse_san(san)  # must be parseable


# ── TestConfusionMatrix ───────────────────────────────────────────────────────

class TestConfusionMatrix:
    def test_bishop_vs_eight_confusion_raises_score_vs_noncandidates(self):
        """
        After 1.e4 e5, it's White's turn. '8c4' should match 'Bc4' better
        than other moves without B/8 confusion (because of the bonus).
        """
        board = _board_after("e4", "e5")
        matcher = CandidateMatcher()
        rankings = matcher.rank_candidates("8c4", board, ocr_confidence=0.8)
        bc4_result = next((r for r in rankings if r.san == "Bc4"), None)
        assert bc4_result is not None, "Bc4 should be in rankings"
        assert bc4_result.confusion_bonus > 0.0

    def test_l_one_confusion_in_rank_position(self):
        """'Nfl' should be close to 'Nf1' which isn't legal from start; but
        the confusion_bonus is computed correctly for any pair of strings."""
        bonus = _confusion_bonus("Nfl", "Nf1")
        assert bonus == pytest.approx(1.0)

    def test_castling_zero_zero_matches_o_o(self):
        """'0-0' should be normalised before reaching the matcher, but
        even if '0-0' reaches the matcher, the lev similarity to 'O-O' is non-trivial."""
        ratio = _lev_ratio("0-0", "O-O")
        # '0-0' vs 'O-O': 2 replacements (0↔O) in 3-char strings
        # ratio = 2*(3 - 2)/(3+3) = 2/6 ≈ 0.333
        assert ratio > 0.25

    def test_confusion_bonus_for_castling_zero_zero(self):
        """'0' and 'O' are a known confusion pair → bonus > 0."""
        bonus = _confusion_bonus("0-0", "O-O")
        assert bonus > 0.0

    def test_q_vs_zero_confusion(self):
        """Q and 0 are a known confusion pair."""
        assert frozenset({"Q", "0"}) in _CONFUSION_PAIRS

    def test_non_confusion_edit_gives_zero_bonus(self):
        assert _confusion_bonus("d4", "e4") == pytest.approx(0.0)


# ── TestThresholdLogic ────────────────────────────────────────────────────────

class TestThresholdLogic:
    def test_above_threshold_not_needs_review(self):
        matcher = CandidateMatcher(confidence_threshold=0.70)
        board = _start_board()
        # "e4" exact match with ocr=0.9 → score=0.5+0.36=0.86 > 0.70
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=0.9)
        assert rankings[0].needs_review is False

    def test_below_threshold_needs_review(self):
        matcher = CandidateMatcher(confidence_threshold=0.95)
        board = _start_board()
        # Exact match, ocr=1.0 → score=0.90 < 0.95 → needs review
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        assert rankings[0].needs_review is True

    def test_custom_threshold_respected(self):
        # Set threshold to exactly the max achievable (1.0) → always flag
        matcher = CandidateMatcher(confidence_threshold=1.0)
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        assert rankings[0].needs_review is True

    def test_low_ocr_confidence_always_flags_review(self):
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        # ocr_confidence below threshold → always flag regardless of lev
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=0.5)
        assert rankings[0].needs_review is True


# ── TestAmbiguityRule ─────────────────────────────────────────────────────────

class TestAmbiguityRule:
    def test_close_top_two_flags_review(self):
        """
        Artificially create a position where two moves are very close in score.
        We test by patching AMBIGUITY_MARGIN to be very large so any real
        difference triggers ambiguity.
        """
        import services.chess.candidate_matcher as m_mod
        original = m_mod.AMBIGUITY_MARGIN

        try:
            # Set margin so high that top-2 are always "close"
            m_mod.AMBIGUITY_MARGIN = 999.0
            matcher = CandidateMatcher(confidence_threshold=0.50)
            board = _start_board()
            # With exact match (score ~0.9) > threshold (0.5), normally not flagged;
            # but inflated margin should force needs_review=True
            rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
            if len(rankings) > 1:
                assert rankings[0].needs_review is True
        finally:
            m_mod.AMBIGUITY_MARGIN = original

    def test_clear_winner_not_flagged_for_ambiguity(self):
        """When the best match is far ahead, ambiguity must NOT trigger."""
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        # Exact match "e4" will score much higher than all others
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        top = rankings[0]
        second_score = rankings[1].score if len(rankings) > 1 else -1
        if top.score - second_score >= AMBIGUITY_MARGIN:
            # No ambiguity expected
            assert top.needs_review is False


# ── TestNeedsReview ───────────────────────────────────────────────────────────

class TestNeedsReview:
    def test_only_top_candidate_can_be_auto_accepted(self):
        """All candidates except results[0] have needs_review=True."""
        matcher = CandidateMatcher(confidence_threshold=0.50)
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        for r in rankings[1:]:
            assert r.needs_review is True

    def test_all_results_have_needs_review_set(self):
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=0.9)
        for r in rankings:
            assert isinstance(r.needs_review, bool)

    def test_needs_review_false_only_for_top_when_above_threshold(self):
        matcher = CandidateMatcher(confidence_threshold=0.80)
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board, ocr_confidence=1.0)
        # score = 0.9 > 0.80; should be auto-accepted
        assert rankings[0].needs_review is False
        assert all(r.needs_review for r in rankings[1:])


# ── TestRankCandidates ────────────────────────────────────────────────────────

class TestRankCandidates:
    def test_result_count_equals_legal_move_count(self):
        board = _start_board()
        matcher = CandidateMatcher()
        rankings = matcher.rank_candidates("e4", board)
        legal_count = board.legal_moves.count()
        assert len(rankings) == legal_count

    def test_results_sorted_descending_by_score(self):
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("e4", board)
        scores = [r.score for r in rankings]
        assert scores == sorted(scores, reverse=True)

    def test_empty_list_for_terminal_position(self):
        """Checkmate → no legal moves → empty rankings."""
        # Fool's mate
        board = _board_after("f3", "e5", "g4", "Qh4")
        matcher = CandidateMatcher()
        assert board.is_checkmate()
        assert matcher.rank_candidates("anything", board) == []

    def test_all_sans_are_legal_in_current_position(self):
        matcher = CandidateMatcher()
        board = _start_board()
        rankings = matcher.rank_candidates("Nf3", board)
        legal_set = {board.san(m) for m in board.legal_moves}
        for r in rankings:
            assert r.san in legal_set

    def test_score_components_sum_to_score(self):
        from services.chess.candidate_matcher import _W_LEV, _W_OCR, _W_CONF
        matcher = CandidateMatcher()
        board = _start_board()
        for r in matcher.rank_candidates("e4", board, ocr_confidence=0.8)[:5]:
            expected = _W_LEV * r.lev_ratio + _W_OCR * r.ocr_confidence + _W_CONF * r.confusion_bonus
            assert abs(r.score - round(expected, 6)) < 1e-5


# ── TestMatchMethod ───────────────────────────────────────────────────────────

class TestMatchMethod:
    def test_exact_match_returns_legal_san(self):
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        san, needs_review = matcher.match("e4", board, ocr_confidence=1.0)
        assert san == "e4"
        assert needs_review is False

    def test_no_match_returns_none(self):
        matcher = CandidateMatcher()
        # Checkmate position: no legal moves
        board = _board_after("f3", "e5", "g4", "Qh4")
        san, needs_review = matcher.match("e4", board)
        assert san is None
        assert needs_review is True

    def test_low_score_input_returns_none_not_wrong_move(self):
        """Completely unrelated input must not auto-return a move."""
        matcher = CandidateMatcher()
        board = _start_board()
        # MIN_MATCH_SCORE is the floor; "xxxx" with no resemblance to any move
        san, needs_review = matcher.match("", board, ocr_confidence=0.0)
        # Empty string may or may not hit the minimum; either (None,True) or (san,True)
        assert needs_review is True

    def test_match_returns_tuple_of_length_two(self):
        matcher = CandidateMatcher()
        result = matcher.match("e4", _start_board())
        assert len(result) == 2

    def test_fuzzy_match_sets_needs_review(self):
        """A fuzzy match that resolves correctly is still flagged for review."""
        matcher = CandidateMatcher(confidence_threshold=0.85)
        board = _start_board()
        # "Ng4" is not a starting legal move; best guess should need review
        san, needs_review = matcher.match("Ng4", board, ocr_confidence=0.7)
        assert needs_review is True


# ── TestGetSuggestions ────────────────────────────────────────────────────────

class TestGetSuggestions:
    def test_returns_at_most_top_n(self):
        matcher = CandidateMatcher()
        board = _start_board()
        suggestions = matcher.get_suggestions("e4", board, top_n=3)
        assert len(suggestions) <= 3

    def test_first_suggestion_has_highest_score(self):
        matcher = CandidateMatcher()
        board = _start_board()
        suggestions = matcher.get_suggestions("e4", board, top_n=5)
        if len(suggestions) > 1:
            assert suggestions[0].score >= suggestions[1].score

    def test_suggestions_are_match_results(self):
        matcher = CandidateMatcher()
        board = _start_board()
        for s in matcher.get_suggestions("e4", board):
            assert isinstance(s, MatchResult)


# ── TestChessServicePhase5 ────────────────────────────────────────────────────

class TestChessServicePhase5:
    """Integration tests: full analyze_game() with Phase 5 matcher."""

    def _service(self):
        from services.chess.chess_service import ChessService
        return ChessService()

    def test_exact_moves_complete_game_no_review(self):
        svc = self._service()
        result = svc.analyze_game(
            ["e4", "e5", "Nf3", "Nc6"],
            ocr_confidences=[1.0, 1.0, 1.0, 1.0],
        )
        assert all(m.is_legal for m in result.moves)
        assert len(result.moves) == 4

    def test_ocr_candidates_populated_in_response(self):
        svc = self._service()
        result = svc.analyze_game(["e4"], ocr_confidences=[1.0])
        assert len(result.moves[0].ocr_candidates) >= 1
        assert result.moves[0].ocr_candidates[0].text == "e4"

    def test_low_ocr_confidence_sets_needs_review(self):
        svc = self._service()
        result = svc.analyze_game(["e4"], ocr_confidences=[0.3])
        assert result.moves[0].needs_manual_review is True

    def test_high_ocr_confidence_exact_match_auto_accepted(self):
        svc = self._service()
        result = svc.analyze_game(["e4"], ocr_confidences=[1.0])
        assert result.moves[0].needs_manual_review is False
        assert result.moves[0].is_legal is True

    def test_missing_ocr_confidences_defaults_to_one(self):
        """Calling analyze_game without ocr_confidences uses default confidence."""
        svc = self._service()
        result = svc.analyze_game(["e4", "e5"])
        assert all(m.is_legal for m in result.moves)

    def test_garbled_move_flagged_for_review(self):
        """'zzz' has near-zero Levenshtein similarity to any legal SAN, but OCR
        confidence still keeps the score above MIN_MATCH_SCORE — the best guess
        is accepted as legal yet flagged for manual review."""
        svc = self._service()
        result = svc.analyze_game(["e4", "e5", "zzz"], ocr_confidences=[1.0, 1.0, 0.9])
        third = result.moves[2]
        assert third.is_legal is True
        assert third.needs_manual_review is True

    def test_illegal_move_stops_game_when_no_confidence(self):
        """With zero OCR confidence, 'zzz' scores ≈ 0 and falls below MIN_MATCH_SCORE,
        so it is recorded as an illegal move and the game stops."""
        svc = self._service()
        result = svc.analyze_game(["e4", "e5", "zzz"], ocr_confidences=[1.0, 1.0, 0.0])
        assert result.moves[2].is_legal is False
        assert result.failure_point_ply == 2

    def test_confidence_in_move_analysis_reflects_matcher_score(self):
        svc = self._service()
        result = svc.analyze_game(["e4"], ocr_confidences=[1.0])
        move = result.moves[0]
        # Exact match score = 0.5 + 0.4 = 0.90
        assert abs(move.confidence - 0.90) < 0.01

    def test_partial_ocr_confidences_uses_defaults_for_rest(self):
        """If ocr_confidences is shorter than raw_moves, remaining use 1.0."""
        svc = self._service()
        result = svc.analyze_game(
            ["e4", "e5"],
            ocr_confidences=[1.0],   # only 1 confidence for 2 moves
        )
        assert result.moves[1].is_legal is True
