"""
Candidate matching: map normalized OCR text to a legal SAN move.

Scoring formula
───────────────
    score = lev_ratio * 0.5 + ocr_confidence * 0.4 + confusion_bonus * 0.1

    lev_ratio      — Levenshtein similarity [0, 1]  (1 = identical strings)
    ocr_confidence — Confidence from OCR provider   [0, 1]
    confusion_bonus — Fraction of edit operations explained by known OCR
                      confusions (e.g. B↔8, O↔0, l↔1)

Maximum achievable score: 1.0 (identical strings, perfect OCR, all edits are
known confusions).  A typical high-quality exact match scores ~0.90.

Auto-accept threshold
──────────────────────
    settings.OCR_CONFIDENCE_THRESHOLD (default 0.85)
    Score ≥ threshold → auto-accepted (needs_review = False).
    Score < threshold → flagged for arbiter review.

Ambiguity rule
───────────────
    If the top-2 candidate scores are within AMBIGUITY_MARGIN (0.05) of each
    other, the top candidate is flagged for review even when its score is above
    the threshold.  Two plausible moves in a close race require human judgement.

Key constraint
───────────────
    The matcher ONLY ranks moves from board.legal_moves.  It never generates
    move hypotheses of its own.  Every returned MatchResult.san is guaranteed
    to be accepted by board.parse_san().
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, replace
from typing import List, Optional, Tuple

import chess

from config import settings
from schemas.analysis import ReviewReason

logger = logging.getLogger(__name__)

# ── Scoring weights ───────────────────────────────────────────────────────────

_W_LEV: float = 0.5    # Levenshtein similarity weight
_W_OCR: float = 0.4    # OCR provider confidence weight
_W_CONF: float = 0.1   # Confusion-matrix bonus weight

# Top-2 scores within this margin → ambiguous → needs review.
AMBIGUITY_MARGIN: float = 0.05

# Minimum score to return any match (below this → no candidate found).
# Avoids returning a completely unrelated move with near-zero Levenshtein
# similarity as "the best guess".
MIN_MATCH_SCORE: float = 0.10


# ── Result type ───────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class MatchResult:
    """
    Full scoring breakdown for one legal SAN candidate.

    Only results[0] (the top-ranked candidate) is authoritative for
    needs_review — all other candidates have needs_review=True.
    """
    san: str               # Legal SAN from board.legal_moves
    score: float           # Final weighted score [0, 1]
    lev_ratio: float       # Levenshtein similarity component
    ocr_confidence: float  # OCR provider confidence (same for all candidates per cell)
    confusion_bonus: float # Confusion-matrix bonus component
    needs_review: bool     # True → arbiter must verify this move
    review_reasons: Tuple[ReviewReason, ...] = ()


# ── Levenshtein (with difflib fallback) ───────────────────────────────────────

try:
    import Levenshtein as _lev_lib
    _HAS_LEVENSHTEIN = True
except ImportError:  # pragma: no cover
    _HAS_LEVENSHTEIN = False
    import difflib as _difflib
    logger.warning(
        "python-levenshtein not installed; using difflib.SequenceMatcher. "
        "Confusion-matrix bonuses will be disabled. "
        "Install with:  pip install python-levenshtein"
    )


def _lev_ratio(a: str, b: str) -> float:
    """Return Levenshtein similarity [0, 1]; 1.0 = identical."""
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    if _HAS_LEVENSHTEIN:
        return _lev_lib.ratio(a, b)
    return _difflib.SequenceMatcher(None, a, b).ratio()  # type: ignore[union-attr]


def _editops(a: str, b: str) -> List[Tuple[str, int, int]]:
    """
    Return the list of edit operations that transform a into b.
    Each element is (op, src_pos, dst_pos) where op is 'replace',
    'insert', or 'delete'.
    """
    if not _HAS_LEVENSHTEIN:
        ops: List[Tuple[str, int, int]] = []
        matcher = _difflib.SequenceMatcher(None, a, b)  # type: ignore[name-defined]
        for tag, i1, i2, j1, j2 in matcher.get_opcodes():
            if tag == "equal":
                continue
            if tag == "replace":
                paired = min(i2 - i1, j2 - j1)
                for offset in range(paired):
                    ops.append(("replace", i1 + offset, j1 + offset))
                for i in range(i1 + paired, i2):
                    ops.append(("delete", i, j1 + paired))
                for j in range(j1 + paired, j2):
                    ops.append(("insert", i1 + paired, j))
            elif tag == "delete":
                for i in range(i1, i2):
                    ops.append(("delete", i, j1))
            elif tag == "insert":
                for j in range(j1, j2):
                    ops.append(("insert", i1, j))
        return ops
    return _lev_lib.editops(a, b)  # type: ignore[return-value]


# ── Chess-specific confusion matrix ───────────────────────────────────────────
#
# Maps OCR character → list of characters it is commonly confused with.
# Bidirectional: if A↔B is a confusion, both A:[B] and B:[A] are listed.
#
# Confusion sources:
#   B↔8, B↔3  — Bishop piece letter vs digits (similar curves in handwriting)
#   l↔1↔I     — lowercase-L, digit-one, uppercase-I (nearly identical)
#   O↔0↔Q     — castling O, zero, Queen (large round shapes)
#   N↔M, N↔H  — Knight (knight head shape resembles M/H)
#   R↔K, R↔P  — Rook vs King/Pawn (short vertical strokes)
#   x↔X↔+↔×   — capture/check/multiplication symbols
#   5↔S        — digit-five vs letter-S (mirror-like)
#   6↔b        — digit-six vs lowercase-b
#   d↔cl       — handwriting ligature
#

CONFUSION_MATRIX: dict[str, list[str]] = {
    "B": ["8", "3"],
    "8": ["B"],
    "3": ["B"],
    "l": ["1", "I"],
    "1": ["l", "I"],
    "I": ["l", "1"],
    "O": ["0", "Q"],
    "0": ["O"],
    "Q": ["O", "0"],
    "N": ["M", "H"],
    "M": ["N"],
    "H": ["N"],
    "R": ["K", "P"],
    "K": ["R"],
    "P": ["R"],
    "x": ["X", "+", "\u00d7"],   # × (multiplication sign)
    "X": ["x"],
    "+": ["x"],
    "\u00d7": ["x"],
    "5": ["S"],
    "S": ["5"],
    "6": ["b"],
    "b": ["6"],
}

# Pre-built frozenset lookup for O(1) confusion-pair checks.
_CONFUSION_PAIRS: frozenset[frozenset] = frozenset(
    frozenset({ch, other})
    for ch, others in CONFUSION_MATRIX.items()
    for other in others
)


def _confusion_bonus(ocr: str, candidate: str) -> float:
    """
    Return the fraction of edit operations (from the Levenshtein alignment)
    that are explained by known OCR confusion pairs.

    Examples:
        _confusion_bonus("Bf3", "8f3")  → 1.0  (1 op, 1 confusion: B↔8)
        _confusion_bonus("Nfl", "Nf1")  → 1.0  (1 op, 1 confusion: l↔1)
        _confusion_bonus("Nf3", "Ng3")  → 0.0  (1 op, not a known confusion)
        _confusion_bonus("e4",  "e4")   → 0.0  (no edits, no bonus needed)

    Uses python-Levenshtein when installed, otherwise a SequenceMatcher-based
    fallback.
    """
    if ocr == candidate:
        return 0.0  # exact match; no confusion bonus needed

    ops = _editops(ocr, candidate)
    if not ops:
        return 0.0

    replace_ops = [(i, j) for op, i, j in ops if op == "replace"]
    if not replace_ops:
        # Only insertions/deletions — length mismatch, no character confusion
        return 0.0

    confused = sum(
        1
        for i, j in replace_ops
        if i < len(ocr) and j < len(candidate)
        and frozenset({ocr[i], candidate[j]}) in _CONFUSION_PAIRS
    )

    # Normalise over ALL edit ops (not just replace) — pure length mismatches
    # (insert/delete) dilute the bonus, which is correct: an extra character
    # is a different kind of error from a character confusion.
    return confused / len(ops)


# ── Matcher ───────────────────────────────────────────────────────────────────


class CandidateMatcher:
    """
    Rank all legal moves in a position by how likely they are to correspond
    to a given normalized OCR string.

    Usage:
        matcher = CandidateMatcher()
        rankings = matcher.rank_candidates("8f3", board, ocr_confidence=0.82)
        best = rankings[0]   # MatchResult(san="Bf3", score=0.81, needs_review=True)
    """

    def __init__(self, confidence_threshold: Optional[float] = None) -> None:
        self.confidence_threshold: float = (
            confidence_threshold
            if confidence_threshold is not None
            else settings.OCR_CONFIDENCE_THRESHOLD
        )

    # ── Public API ────────────────────────────────────────────────────────────

    def rank_candidates(
        self,
        normalized_text: str,
        board: chess.Board,
        ocr_confidence: float = 1.0,
    ) -> List[MatchResult]:
        """
        Score every legal SAN against *normalized_text* and return them sorted
        by score descending.

        Args:
            normalized_text: Output of MoveNormalizer.normalize().
            board:           Current position — source of legal moves.
            ocr_confidence:  OCR provider confidence for this cell [0, 1].

        Returns:
            List of MatchResult sorted by score descending.
            Empty only when the position has no legal moves (terminal state).
        """
        legal_sans = self._legal_sans(board)
        if not legal_sans:
            return []

        raw: List[MatchResult] = []
        normalized_bare = normalized_text.rstrip("+#")
        for san in legal_sans:
            # Strip check (+/++) and checkmate (#) annotations before comparing:
            # OCR almost never captures these symbols, and the piece/square
            # coordinates are sufficient to identify the move uniquely.
            san_bare = san.rstrip("+#")
            lev = _lev_ratio(normalized_bare, san_bare)
            cb = _confusion_bonus(normalized_bare, san_bare)
            score = _W_LEV * lev + _W_OCR * ocr_confidence + _W_CONF * cb
            raw.append(MatchResult(
                san=san,
                score=round(score, 6),
                lev_ratio=round(lev, 6),
                ocr_confidence=ocr_confidence,
                confusion_bonus=round(cb, 6),
                needs_review=False,  # filled in the next pass
                review_reasons=(),
            ))

        raw.sort(key=lambda r: r.score, reverse=True)
        return self._mark_review(raw, ocr_confidence)

    def match(
        self,
        normalized_text: str,
        board: chess.Board,
        ocr_confidence: float = 1.0,
    ) -> Tuple[Optional[str], bool]:
        """
        Return the best matching legal SAN and whether it needs arbiter review.

        Backward-compatible with the Phase 1 signature.

        Args:
            normalized_text: Output of MoveNormalizer.normalize().
            board:           Current position (move NOT yet pushed).
            ocr_confidence:  OCR provider confidence [0, 1].

        Returns:
            (san, needs_review) where san is a legal SAN string, or
            (None, True) when no candidate reaches MIN_MATCH_SCORE.
        """
        rankings = self.rank_candidates(normalized_text, board, ocr_confidence)
        if not rankings:
            return None, True

        best = rankings[0]
        if best.score < MIN_MATCH_SCORE:
            return None, True

        return best.san, best.needs_review

    def get_suggestions(
        self,
        normalized_text: str,
        board: chess.Board,
        ocr_confidence: float = 1.0,
        top_n: int = 5,
    ) -> List[MatchResult]:
        """Return the top-N ranked MatchResults (previously returned unranked moves)."""
        return self.rank_candidates(normalized_text, board, ocr_confidence)[:top_n]

    # ── Private helpers ───────────────────────────────────────────────────────

    def _mark_review(
        self,
        sorted_results: List[MatchResult],
        ocr_confidence: float,
    ) -> List[MatchResult]:
        """
        Assign needs_review to each result.

        Rules applied to results[0] (the best candidate):
          • score < confidence_threshold → always flag
          • ocr_confidence < confidence_threshold → always flag (OCR uncertain)
          • top-2 scores within AMBIGUITY_MARGIN → flag (two equally plausible moves)

        All results[1:] have needs_review=True (they are not the chosen match).
        """
        if not sorted_results:
            return []

        threshold = self.confidence_threshold
        top = sorted_results[0]
        second_score = sorted_results[1].score if len(sorted_results) > 1 else -1.0

        ambiguous = (
            top.score >= threshold
            and (top.score - second_score) < AMBIGUITY_MARGIN
        )

        best_needs_review: bool = (
            top.score < threshold
            or ocr_confidence < threshold
            or ambiguous
        )

        top_reasons: List[ReviewReason] = []
        if top.score < threshold:
            top_reasons.append(ReviewReason.BELOW_THRESHOLD)
        if ocr_confidence < threshold:
            top_reasons.append(ReviewReason.LOW_OCR_CONFIDENCE)
        if ambiguous:
            top_reasons.append(ReviewReason.AMBIGUOUS_TOP_TWO)

        marked: List[MatchResult] = []
        for i, r in enumerate(sorted_results):
            if i == 0:
                marked.append(replace(
                    r,
                    needs_review=best_needs_review,
                    review_reasons=tuple(top_reasons),
                ))
            else:
                marked.append(replace(r, needs_review=True, review_reasons=()))
        return marked

    @staticmethod
    def _legal_sans(board: chess.Board) -> List[str]:
        return [board.san(m) for m in board.legal_moves]
