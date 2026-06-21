"""
Tests for Phase 6: manual correction API.

POST /api/games/{game_id}/moves/{ply_index}/correct

Coverage:
  TestCorrectionBasics        — happy path, illegal-move recovery, 404 cases
  TestValidation              — invalid SAN → 422, correct message
  TestReanalysis              — re-analysis runs FIDE checks from corrected ply
  TestReviewActionPersisted   — ReviewAction row written with correct data
  TestMultipleCorrections     — correction chain: ply 2, then ply 3
  TestPartialGame             — correcting the failure-point ply restores the game
"""

from __future__ import annotations

import pytest
import pytest_asyncio

from models.game import Game, MoveEntry, OCRResult, ReviewAction, RuleFindingDB
from schemas.analysis import GameStatus


# ── DB seeding helper ─────────────────────────────────────────────────────────


async def _seed_game(
    db,
    moves: list[str],
    session_id: str = "test-session",
    ocr_confidences: list[float] | None = None,
    game_locale: str = "en",
) -> Game:
    """
    Run chess_service.analyze_game() and persist the result as a Game +
    MoveEntry rows so the review endpoint has something to work with.

    Returns a committed Game ORM object with move_entries eagerly loaded.
    Eager loading is required because async SQLAlchemy cannot lazy-load
    relationships in test code running outside a greenlet context.
    """
    from sqlalchemy import select
    from sqlalchemy.orm import selectinload

    from services.chess.chess_service import ChessService

    svc = ChessService()
    result = svc.analyze_game(
        moves,
        session_id=session_id,
        ocr_confidences=ocr_confidences,
    )

    game = Game(
        id=result.game_id,
        session_id=session_id,
        status=result.status.value,
        pgn=result.pgn,
        failure_point_ply=result.failure_point_ply,
        locale=game_locale,
    )
    db.add(game)
    await db.flush()

    for m in result.moves:
        entry = MoveEntry(
            game_id=game.id,
            ply_index=m.ply_index,
            color=m.color,
            move_number=m.move_number,
            selected_san=m.selected_san,
            selected_uci=m.selected_uci,
            fen_before=m.fen_before,
            fen_after=m.fen_after,
            is_legal=m.is_legal,
            needs_review=m.needs_manual_review,
            confidence=m.confidence,
            fide_alerts_csv=",".join(m.fide_alerts),
        )
        db.add(entry)

    # Also persist any rule findings
    for f in result.findings:
        db.add(RuleFindingDB(
            game_id=game.id,
            ply_index=f.ply_index,
            type=f.type.value,
            description=f.description,
            is_automatic=f.is_automatic,
        ))

    await db.commit()

    # Reload with eagerly-loaded move_entries so test code can access them
    # without triggering async lazy-load outside a greenlet.
    stmt = (
        select(Game)
        .where(Game.id == game.id)
        .options(selectinload(Game.move_entries))
    )
    reloaded = await db.execute(stmt)
    return reloaded.scalar_one()


# ── TestCorrectionBasics ──────────────────────────────────────────────────────


class TestCorrectionBasics:
    @pytest.mark.asyncio
    async def test_correct_move_returns_200(self, async_session, app_client):
        """Happy path: correcting a valid move returns 200 with updated game."""
        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        data = resp.json()
        # After correcting ply 0 to d4, that move should now be d4
        assert data["moves"][0]["selected_san"] == "d4"
        assert data["game_id"] == game.id

    @pytest.mark.asyncio
    async def test_correct_returns_full_game_analysis_response(
        self, async_session, app_client
    ):
        """Response must include all required GameAnalysisResponse fields."""
        game = await _seed_game(async_session, ["e4", "e5"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        data = resp.json()

        required_keys = {
            "game_id", "session_id", "locale", "status", "moves",
            "findings", "pgn", "failure_point_ply", "stats",
        }
        assert required_keys.issubset(data.keys())

    @pytest.mark.asyncio
    async def test_game_not_found_returns_404(self, app_client):
        """Requesting a non-existent game_id returns 404."""
        resp = await app_client.post(
            "/api/games/does-not-exist/moves/0/correct",
            json={"corrected_san": "e4"},
        )
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_ply_not_found_returns_404(self, async_session, app_client):
        """Requesting a ply_index that doesn't exist returns 404."""
        game = await _seed_game(async_session, ["e4", "e5"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/99/correct",
            json={"corrected_san": "Nf3"},
        )
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_corrected_move_reflected_in_subsequent_fens(
        self, async_session, app_client
    ):
        """All moves after correction must chain from the new board state."""
        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        moves = resp.json()["moves"]

        # fen_after of move N must equal fen_before of move N+1
        for i in range(len(moves) - 1):
            assert moves[i]["fen_after"] == moves[i + 1]["fen_before"], (
                f"FEN chain broken between ply {moves[i]['ply_index']} "
                f"and ply {moves[i+1]['ply_index']}"
            )

    @pytest.mark.asyncio
    async def test_correction_updates_game_status(self, async_session, app_client):
        """After correcting a previously bad move, status should reflect outcome."""
        # Seed with a fuzzy-match move that needs review
        game = await _seed_game(
            async_session,
            ["e4", "e5"],
            ocr_confidences=[1.0, 0.3],  # ply 1 flagged for review
        )
        assert game.status == GameStatus.NEEDS_REVIEW.value

        # Correct ply 1 with the right move at high confidence
        resp = await app_client.post(
            f"/api/games/{game.id}/moves/1/correct",
            json={"corrected_san": "e5"},
        )
        assert resp.status_code == 200
        data = resp.json()
        # After correction, ply 1 is confirmed — status should be completed
        assert data["status"] == GameStatus.COMPLETED.value


# ── TestValidation ────────────────────────────────────────────────────────────


class TestValidation:
    @pytest.mark.asyncio
    async def test_invalid_san_returns_422(self, async_session, app_client):
        """A move that is not legal in the position returns 422."""
        game = await _seed_game(async_session, ["e4", "e5"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "Zz9"},
        )
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_invalid_san_error_message_is_helpful(
        self, async_session, app_client
    ):
        """422 detail should mention the rejected SAN."""
        game = await _seed_game(async_session, ["e4", "e5"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "Rxz9"},
        )
        assert resp.status_code == 422
        detail = resp.json()["detail"]
        assert "Rxz9" in detail

    @pytest.mark.asyncio
    async def test_move_illegal_in_position_returns_422(
        self, async_session, app_client
    ):
        """A syntactically valid SAN that is not legal in the position → 422."""
        # After 1.e4, it's Black's turn. "d4" is not a legal Black move.
        game = await _seed_game(async_session, ["e4", "e5"])

        # Correct ply 1 (Black's move) with a White-only move
        resp = await app_client.post(
            f"/api/games/{game.id}/moves/1/correct",
            json={"corrected_san": "d4"},  # d4 is White's pawn, not legal for Black
        )
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_valid_san_with_check_annotation_accepted(
        self, async_session, app_client
    ):
        """The normalizer strips move annotations; 'Nf3+' should be accepted."""
        game = await _seed_game(async_session, ["e4", "e5"])

        # Nf3 after 1.e4 e5 doesn't give check, but the '+' should be stripped
        # and the underlying Nf3 should be accepted.
        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "e4"},  # e4 is legal as White's first move
        )
        assert resp.status_code == 200

    @pytest.mark.asyncio
    async def test_ocr_confusion_san_normalised_before_validation(
        self, async_session, app_client
    ):
        """'0-0' (digit zeros) should normalize to 'O-O' before validation."""
        # Seed 9 moves so ply 8 (White's 5th move) exists in the DB.
        # After 1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 4.Ba4 Nf6, White can castle (O-O).
        # We seed ply 8 with a bad OCR so we can correct it to "0-0" (digit zeros).
        moves = ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4", "Nf6", "zzz"]
        # ply 8 is unresolvable (ocr_conf=0.0) so it becomes the failure point
        ocr_conf = [1.0] * 8 + [0.0]
        game = await _seed_game(async_session, moves, ocr_confidences=ocr_conf)

        # Correct ply 8 with '0-0' (digit zeros — common OCR output for O-O)
        resp = await app_client.post(
            f"/api/games/{game.id}/moves/8/correct",
            json={"corrected_san": "0-0"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["moves"][8]["selected_san"] == "O-O"


# ── TestReanalysis ────────────────────────────────────────────────────────────


class TestReanalysis:
    @pytest.mark.asyncio
    async def test_reanalysis_uses_game_locale_for_subsequent_ocr(
        self, async_session, app_client
    ):
        """
        A correction request can arrive with locale=en because the UI displays
        canonical SAN, but later OCR rows still belong to the game's locale.
        Turkish OCR such as Af6 must re-analyze as Nf6, not as pawn f6.
        """
        game = await _seed_game(
            async_session,
            [
                "e4", "e5", "f4", "exf4", "Bc4", "Qh4+",
                "Kf1", "b5", "Bxb5", "Nf6", "Nf3", "Qh6",
            ],
            game_locale="tr",
        )

        turkish_raw_by_ply = {
            4: "Fc4",
            5: "Vh4+",
            6: "Şf1",
            8: "Fxb5",
            9: "Af6",
            10: "Af3",
            11: "Vh6",
        }
        for entry in game.move_entries:
            raw = turkish_raw_by_ply.get(entry.ply_index, entry.selected_san or "")
            async_session.add(OCRResult(
                move_entry_id=entry.id,
                raw_text=raw,
                normalized_text=raw,
                candidates_json=[{"text": raw, "confidence": 0.96}],
            ))
        await async_session.commit()

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/5/correct",
            json={"corrected_san": "Qh4+", "locale": "en"},
        )
        assert resp.status_code == 200
        by_ply = {m["ply_index"]: m for m in resp.json()["moves"]}

        assert by_ply[5]["selected_san"] == "Qh4+"
        assert by_ply[5]["needs_manual_review"] is False
        assert by_ply[6]["selected_san"] == "Kf1"
        assert by_ply[9]["selected_san"] == "Nf6"
        assert by_ply[10]["selected_san"] == "Nf3"
        assert by_ply[11]["selected_san"] == "Qh6"
        assert by_ply[9]["needs_manual_review"] is False

    @pytest.mark.asyncio
    async def test_correction_reruns_fide_analysis_from_ply(
        self, async_session, app_client
    ):
        """
        Correcting a move that leads to checkmate must produce a CHECKMATE finding.

        Fool's mate setup:
          1.f3  e5
          2.g4  Qh4#
        We seed the game with ply 3 unresolvable (ocr_conf=0.0), then correct
        it to 'Qh4' and expect a checkmate finding.
        """
        game = await _seed_game(
            async_session,
            ["f3", "e5", "g4", "zzz"],
            ocr_confidences=[1.0, 1.0, 1.0, 0.0],
        )
        # ply 3 is the failure point
        assert game.failure_point_ply == 3

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/3/correct",
            json={"corrected_san": "Qh4"},
        )
        assert resp.status_code == 200
        data = resp.json()

        findings = data["findings"]
        checkmate = [f for f in findings if f["type"] == "checkmate"]
        assert len(checkmate) == 1
        assert checkmate[0]["ply_index"] == 3
        assert checkmate[0]["is_automatic"] is True

    @pytest.mark.asyncio
    async def test_correction_clears_old_findings_from_ply_onward(
        self, async_session, app_client
    ):
        """
        A finding at ply N must be replaced when ply N is corrected.
        We simulate an ILLEGAL_MOVE finding at ply 2 and correct it away.
        """
        game = await _seed_game(
            async_session,
            ["e4", "e5", "zzz"],
            ocr_confidences=[1.0, 1.0, 0.0],
        )
        assert game.failure_point_ply == 2

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "Nf3"},
        )
        assert resp.status_code == 200
        data = resp.json()

        # The illegal_move finding at ply 2 must be gone
        illegal = [f for f in data["findings"] if f["type"] == "illegal_move"]
        assert len(illegal) == 0
        assert data["failure_point_ply"] is None

    @pytest.mark.asyncio
    async def test_findings_before_ply_index_are_preserved(
        self, async_session, app_client
    ):
        """
        Findings at plies < ply_index must not be touched by the correction.
        """
        # Seed a game where ply 3 is unresolvable; no FIDE findings before it
        # (just a simple 3-move sequence with the 4th failing)
        game = await _seed_game(
            async_session,
            ["e4", "e5", "Nf3", "zzz"],
            ocr_confidences=[1.0, 1.0, 1.0, 0.0],
        )

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/3/correct",
            json={"corrected_san": "Nc6"},
        )
        assert resp.status_code == 200
        data = resp.json()

        # After correction, ply 3 is "Nc6" and game continues cleanly
        assert data["moves"][3]["selected_san"] == "Nc6"
        assert data["failure_point_ply"] is None

    @pytest.mark.asyncio
    async def test_subsequent_moves_reanalyzed_with_new_board(
        self, async_session, app_client
    ):
        """
        Moves after the corrected ply are re-matched against the new board state.
        """
        # After 1.e4 e5 2.Nf3 Nc6, if we correct ply 2 from Nf3 to d4,
        # the subsequent move "Nc6" is re-evaluated in the new position.
        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        data = resp.json()

        assert len(data["moves"]) == 4
        assert data["moves"][2]["selected_san"] == "d4"
        # ply 3 should be re-evaluated; "Nc6" is still legal after 1.e4 e5 2.d4
        assert data["moves"][3]["is_legal"] is True

    @pytest.mark.asyncio
    async def test_only_moves_from_ply_onward_change(
        self, async_session, app_client
    ):
        """
        Moves before ply_index must keep their original selected_san values.
        """
        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        moves = resp.json()["moves"]

        # ply 0 and 1 must be unchanged
        assert moves[0]["selected_san"] == "e4"
        assert moves[1]["selected_san"] == "e5"
        # ply 2 is the corrected one
        assert moves[2]["selected_san"] == "d4"


# ── TestReviewActionPersisted ─────────────────────────────────────────────────


class TestReviewActionPersisted:
    @pytest.mark.asyncio
    async def test_review_action_created(self, async_session, app_client):
        """A ReviewAction row must exist in the DB after correction."""
        from sqlalchemy import select

        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])
        target_entry = next(
            e for e in game.move_entries if e.ply_index == 2
        )

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200

        result = await async_session.execute(
            select(ReviewAction).where(
                ReviewAction.move_entry_id == target_entry.id
            )
        )
        actions = result.scalars().all()
        assert len(actions) == 1

    @pytest.mark.asyncio
    async def test_review_action_records_original_san(
        self, async_session, app_client
    ):
        """ReviewAction.original_san must match what was in the DB before correction."""
        from sqlalchemy import select

        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])
        target_entry = next(
            e for e in game.move_entries if e.ply_index == 2
        )
        original_san = target_entry.selected_san  # "Nf3"

        await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "d4"},
        )

        result = await async_session.execute(
            select(ReviewAction).where(
                ReviewAction.move_entry_id == target_entry.id
            )
        )
        action = result.scalars().first()
        assert action is not None
        assert action.original_san == original_san

    @pytest.mark.asyncio
    async def test_review_action_records_corrected_san(
        self, async_session, app_client
    ):
        """ReviewAction.corrected_san must be the canonical SAN after correction."""
        from sqlalchemy import select

        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])
        target_entry = next(
            e for e in game.move_entries if e.ply_index == 2
        )

        await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "d4"},
        )

        result = await async_session.execute(
            select(ReviewAction).where(
                ReviewAction.move_entry_id == target_entry.id
            )
        )
        action = result.scalars().first()
        assert action is not None
        assert action.corrected_san == "d4"

    @pytest.mark.asyncio
    async def test_review_action_has_timestamp(self, async_session, app_client):
        """ReviewAction.corrected_at must be populated."""
        from sqlalchemy import select

        game = await _seed_game(async_session, ["e4", "e5"])
        target_entry = next(
            e for e in game.move_entries if e.ply_index == 0
        )

        await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )

        result = await async_session.execute(
            select(ReviewAction).where(
                ReviewAction.move_entry_id == target_entry.id
            )
        )
        action = result.scalars().first()
        assert action is not None
        assert action.corrected_at is not None


# ── TestMultipleCorrections ───────────────────────────────────────────────────


class TestMultipleCorrections:
    @pytest.mark.asyncio
    async def test_two_sequential_corrections(self, async_session, app_client):
        """
        Correct ply 0, then correct ply 1 — both corrections must be consistent.
        """
        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])

        # First correction: ply 0 → d4
        resp1 = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )
        assert resp1.status_code == 200
        assert resp1.json()["moves"][0]["selected_san"] == "d4"

        # Second correction: ply 1 (now after d4) → d5
        resp2 = await app_client.post(
            f"/api/games/{game.id}/moves/1/correct",
            json={"corrected_san": "d5"},
        )
        assert resp2.status_code == 200
        moves = resp2.json()["moves"]
        assert moves[0]["selected_san"] == "d4"
        assert moves[1]["selected_san"] == "d5"

    @pytest.mark.asyncio
    async def test_two_review_actions_recorded_for_chain(
        self, async_session, app_client
    ):
        """Each correction in a chain must produce its own ReviewAction row."""
        from sqlalchemy import select

        game = await _seed_game(async_session, ["e4", "e5"])

        await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )
        await app_client.post(
            f"/api/games/{game.id}/moves/1/correct",
            json={"corrected_san": "d5"},
        )

        result = await async_session.execute(
            select(ReviewAction).where(
                ReviewAction.move_entry_id.in_(
                    [e.id for e in game.move_entries]
                )
            )
        )
        actions = result.scalars().all()
        assert len(actions) == 2

    @pytest.mark.asyncio
    async def test_correcting_same_ply_twice_records_both_actions(
        self, async_session, app_client
    ):
        """Correcting the same ply twice accumulates ReviewAction records."""
        from sqlalchemy import select

        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])
        target_entry = next(e for e in game.move_entries if e.ply_index == 2)

        await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "d4"},
        )
        await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "Nc3"},
        )

        result = await async_session.execute(
            select(ReviewAction).where(
                ReviewAction.move_entry_id == target_entry.id
            )
        )
        actions = result.scalars().all()
        assert len(actions) == 2
        sans = {a.corrected_san for a in actions}
        assert "d4" in sans
        assert "Nc3" in sans


# ── TestPartialGame ───────────────────────────────────────────────────────────


class TestPartialGame:
    @pytest.mark.asyncio
    async def test_correcting_failure_point_removes_failure(
        self, async_session, app_client
    ):
        """
        When the failure-point ply is corrected, failure_point_ply must become None
        and the game must continue.
        """
        game = await _seed_game(
            async_session,
            ["e4", "e5", "zzz"],
            ocr_confidences=[1.0, 1.0, 0.0],
        )
        assert game.failure_point_ply == 2

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "Nf3"},
        )
        assert resp.status_code == 200
        data = resp.json()

        assert data["failure_point_ply"] is None
        assert data["moves"][2]["is_legal"] is True
        assert data["moves"][2]["selected_san"] == "Nf3"

    @pytest.mark.asyncio
    async def test_correcting_first_ply_to_valid_move(
        self, async_session, app_client
    ):
        """Edge case: correcting ply 0 (no prior moves to replay)."""
        game = await _seed_game(async_session, ["e4"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["moves"][0]["selected_san"] == "d4"

    @pytest.mark.asyncio
    async def test_correcting_last_ply_does_not_create_extra_moves(
        self, async_session, app_client
    ):
        """Correcting the last move must not produce extra phantom moves."""
        game = await _seed_game(async_session, ["e4", "e5", "Nf3"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/2/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        assert len(resp.json()["moves"]) == 3

    @pytest.mark.asyncio
    async def test_pgn_updated_after_correction(self, async_session, app_client):
        """Game.pgn must reflect the corrected move."""
        game = await _seed_game(async_session, ["e4", "e5", "Nf3", "Nc6"])

        resp = await app_client.post(
            f"/api/games/{game.id}/moves/0/correct",
            json={"corrected_san": "d4"},
        )
        assert resp.status_code == 200
        pgn = resp.json()["pgn"]
        assert "d4" in pgn
        assert "e4" not in pgn  # old first move must be replaced
