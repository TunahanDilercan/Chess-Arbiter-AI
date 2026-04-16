"""
FIDE rule analysis for a given board position.

This module is the single source of truth for FIDE draw and termination
detection. It is called by chess_service.py after every move push.

Critical rule: the caller MUST use the correct python-chess method and
label each finding as automatic or claimable — never mix them up.

  AUTOMATIC (game ends unconditionally, arbiter enforces):
    board.is_fivefold_repetition()   → FIDE Art. 9.6.1
    board.is_seventyfive_moves()     → FIDE Art. 9.6.2
    board.is_checkmate()
    board.is_stalemate()
    board.is_insufficient_material()

  CLAIMABLE (player opportunity, NOT enforced — arbiter may be notified):
    board.can_claim_threefold_repetition()  → FIDE Art. 9.2.1
    board.can_claim_fifty_moves()           → FIDE Art. 9.3

Deduplication contract
──────────────────────
analyze_position() receives a *mutable* seen_types set from the caller
(chess_service.analyze_game).  Before appending any finding, it checks
whether that FindingType is already present in seen_types.

  • If already seen → the alert/finding is silently skipped.
  • If new → the type is added to seen_types and the finding is appended.

This guarantees that a condition that persists across multiple plies
(e.g. threefold repetition still available on moves 40, 41, 42 …) only
produces ONE finding, at the ply where it was first detected.

For automatic game-ending rules the deduplication is logically redundant
(is_game_over() stops the loop after the first detection), but it is
applied uniformly for correctness and future-proofing.
"""

from __future__ import annotations

from typing import List, Optional, Set, Tuple

import chess

from schemas.analysis import FindingType, RuleFinding


class FIDEAnalyzer:
    """
    Checks all FIDE draw and termination conditions after a move is pushed.

    Usage (chess_service.py owns the seen_types set):

        seen: set[FindingType] = set()
        analyzer = FIDEAnalyzer()

        for ply, … in enumerate(moves):
            alerts, findings = analyzer.analyze_position(board, ply, seen)
            # findings contains AT MOST ONE entry per FindingType across all plies.

    Returns:
        alerts   — short string codes for the per-move `fide_alerts` field
        findings — RuleFinding objects to append to the game findings list
    """

    def analyze_position(
        self,
        board: chess.Board,
        ply_index: int,
        seen_types: Optional[Set[FindingType]] = None,
    ) -> Tuple[List[str], List[RuleFinding]]:
        """
        Inspect the board state after a move has been pushed.

        Checks are ordered: terminal states first (checkmate, stalemate,
        insufficient material), then automatic draws, then claimable draws.
        Once a terminal state is found we return immediately — subsequent
        conditions cannot coexist with a finished game.

        Deduplication: any FindingType already present in seen_types is
        skipped.  seen_types is updated in-place for each new finding.

        Args:
            board:      Position AFTER the move has been pushed.
            ply_index:  0-based half-move index.
            seen_types: Mutable set shared across the entire game analysis.
                        Updated in-place; owned by the caller.
        """
        # When called without a shared seen_types set (e.g. from tests or
        # one-off callers), create a local set so deduplication still works
        # within the single call but has no cross-call effect.
        if seen_types is None:
            seen_types = set()

        alerts: List[str] = []
        findings: List[RuleFinding] = []

        def _add(
            alert_code: str,
            finding_type: FindingType,
            description: str,
            is_automatic: bool,
        ) -> bool:
            """
            Append a finding if its type has not been seen before.

            Returns True if the finding was new and was added, False if it
            was a duplicate and was skipped.  Either way, the alert code is
            appended (for per-move fide_alerts) only when the finding is new.
            """
            if finding_type in seen_types:
                return False
            seen_types.add(finding_type)
            alerts.append(alert_code)
            findings.append(RuleFinding(
                type=finding_type,
                ply_index=ply_index,
                description=description,
                is_automatic=is_automatic,
            ))
            return True

        # ── Terminal states ───────────────────────────────────────────────────
        # These end the game unconditionally and have priority over everything.

        if board.is_checkmate():
            winner = "White" if board.turn == chess.BLACK else "Black"
            _add(
                "checkmate",
                FindingType.CHECKMATE,
                f"Checkmate — {winner} wins.",
                is_automatic=True,
            )
            return alerts, findings  # nothing else is relevant after checkmate

        if board.is_stalemate():
            _add(
                "stalemate",
                FindingType.STALEMATE,
                "Stalemate — draw.",
                is_automatic=True,
            )
            return alerts, findings

        if board.is_insufficient_material():
            _add(
                "insufficient_material",
                FindingType.INSUFFICIENT_MATERIAL,
                "Insufficient material — draw.",
                is_automatic=True,
            )
            return alerts, findings

        # ── Automatic draws (FIDE Art. 9.6) ──────────────────────────────────
        # These end the game unconditionally regardless of player action.
        # is_automatic = True.  Return immediately to prevent any further
        # checks on the same ply (conditions are mutually exclusive in practice).

        if board.is_fivefold_repetition():
            # FIDE Art. 9.6.1 — automatic, no claim needed
            added = _add(
                "fivefold_automatic",
                FindingType.FIVEFOLD_AUTOMATIC,
                (
                    "Draw by fivefold repetition (FIDE Art. 9.6.1). "
                    "The game ends here automatically regardless of player action."
                ),
                is_automatic=True,
            )
            if added:
                return alerts, findings

        if board.is_seventyfive_moves():
            # FIDE Art. 9.6.2 — automatic, no claim needed
            added = _add(
                "seventy_five_automatic",
                FindingType.SEVENTY_FIVE_AUTOMATIC,
                (
                    "Draw by the 75-move rule (FIDE Art. 9.6.2). "
                    "The game ends here automatically regardless of player action."
                ),
                is_automatic=True,
            )
            if added:
                return alerts, findings

        # ── Claimable draws (FIDE Art. 9.2.1 / 9.3) ─────────────────────────
        # These are player opportunities that do NOT end the game automatically.
        # is_automatic = False.  Both can be true simultaneously.
        #
        # Deduplication prevents the same claimable finding from being repeated
        # on every subsequent ply while the condition remains available.

        if board.can_claim_threefold_repetition():
            # FIDE Art. 9.2.1 — claimable by the player to move
            _add(
                "threefold_claim_available",
                FindingType.THREEFOLD_CLAIM_AVAILABLE,
                (
                    "Threefold repetition draw available (FIDE Art. 9.2.1). "
                    "A player may claim a draw; the game does NOT end automatically. "
                    "Arbiter should be notified if a claim is made."
                ),
                is_automatic=False,
            )

        if board.can_claim_fifty_moves():
            # FIDE Art. 9.3 — claimable by the player to move
            _add(
                "fifty_claim_available",
                FindingType.FIFTY_CLAIM_AVAILABLE,
                (
                    "50-move draw claim available (FIDE Art. 9.3). "
                    "A player may claim a draw; the game does NOT end automatically. "
                    "Arbiter should be notified if a claim is made."
                ),
                is_automatic=False,
            )

        return alerts, findings

    def is_game_over(self, board: chess.Board) -> bool:
        """
        Returns True if the position represents a forced, unconditional game end.

        Used by chess_service.py to stop processing subsequent moves once the
        game has terminated.  Claimable draws do NOT count as game over here —
        the game continues until the player actually claims.
        """
        return (
            board.is_checkmate()
            or board.is_stalemate()
            or board.is_insufficient_material()
            or board.is_fivefold_repetition()
            or board.is_seventyfive_moves()
        )
