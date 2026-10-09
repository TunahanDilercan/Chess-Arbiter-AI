"""Regression tests for persisted OCR/review alignment and job recovery."""
import importlib.util
import io
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
import sqlalchemy as sa
from alembic.migration import MigrationContext
from alembic.operations import Operations
from PIL import Image

from models.game import Game, MoveCrop, MoveEntry, OCRResult, ProcessingJob
from schemas.analysis import AnalysisSource, DrawDecision
from services.chess.chess_service import ChessService
from services.job_service import get_game_full, game_to_response
from services.move_sequence import ocr_input
from tests.test_review import _seed_game


async def add_sources(db, game, texts):
    for entry, text in zip(game.move_entries, texts):
        db.add(OCRResult(move_entry_id=entry.id, raw_text=text, normalized_text=text,
                         candidates_json=[{"text": text, "confidence": 0.99}]))
    await db.commit()


async def correct(client, game, ply, san):
    response = await client.post(
        f"/api/games/{game.id}/moves/{ply}/correct?session_id=test-session",
        json={"corrected_san": san},
    )
    assert response.status_code == 200, response.text
    return response.json()


@pytest.mark.asyncio
async def test_later_human_correction_survives_earlier_edit(async_session, app_client):
    game = await _seed_game(async_session, ["e4", "e5", "Nc3", "Nc6"])
    await add_sources(async_session, game, ["e4", "e5", "Nc3", "Nc6"])
    await correct(app_client, game, 2, "Nf3")
    result = await correct(app_client, game, 0, "d4")
    assert result["moves"][2]["selected_san"] == "Nf3"
    assert not result["moves"][2]["needs_manual_review"]


@pytest.mark.asyncio
async def test_review_response_matches_persisted_flags_and_crops(async_session, app_client):
    game = await _seed_game(async_session, ["e4", "e5", "Nf3"], ocr_confidences=[0.7, 1, 1])
    async_session.add(MoveCrop(move_entry_id=game.move_entries[0].id, crop_image_path="crops/test.png"))
    await async_session.commit()
    response = await correct(app_client, game, 2, "Nf3")
    fresh = game_to_response(await get_game_full(async_session, game.id)).model_dump(mode="json")
    assert response["stats"] == fresh["stats"]
    assert response["status"] == fresh["status"] == "needs_review"
    assert response["moves"][0]["needs_manual_review"]
    assert response["moves"][0]["crop_image_url"]


@pytest.mark.asyncio
async def test_sparse_worker_sequence_stops_and_recovers_without_deleting_tail(async_session, app_client):
    from workers.processing_tasks import _run_analysis
    game = Game(session_id="test-session", locale="en", status="processing")
    async_session.add(game)
    await async_session.flush()
    job = ProcessingJob(game_id=game.id, status="analyzing")
    async_session.add(job)
    for ply, text in [(0, "e4"), (2, "Nf3"), (3, "Nc6")]:
        entry = MoveEntry(game_id=game.id, ply_index=ply, color="white" if ply % 2 == 0 else "black",
                          move_number=ply // 2 + 1, fen_before="", fen_after="", is_legal=False)
        entry.ocr_result = OCRResult(raw_text=text, normalized_text=text,
                                    candidates_json=[{"text": text, "confidence": 0.99}])
        async_session.add(entry)
    await async_session.commit()
    with patch("workers.processing_tasks._publish_status", new_callable=AsyncMock):
        await _run_analysis(async_session, job.id, game.id)
    data = game_to_response(await get_game_full(async_session, game.id))
    assert len(data.moves) == 4
    assert data.failure_point_ply == 1
    assert data.moves[2].selected_san is None
    assert data.moves[2].ocr_raw_text == "Nf3"
    result = await correct(app_client, game, 1, "e5")
    assert [move["selected_san"] for move in result["moves"]] == ["e4", "e5", "Nf3", "Nc6"]


def test_invalidated_confirmation_is_not_replaced_by_fuzzy_match():
    result = ChessService().analyze_game(
        ["d4", "e5", "Bc4", "Nc6"], analysis_source=AnalysisSource.OCR,
        confirmed_moves={2: "Bc4"},
    )
    assert result.failure_point_ply == 2
    assert result.moves[2].selected_san is None


def test_current_draw_claim_not_historical_claim():
    moves = ["Nf3", "Nf6", "Ng1", "Ng8"] * 2 + ["e4"]
    result = ChessService().analyze_game(moves)
    assert result.draw_decision == DrawDecision.NONE
    assert not result.requires_player_claim


def test_english_model_output_is_not_turkish_normalized_twice():
    entry = MoveEntry(confidence=0.99, ocr_result=OCRResult(
        raw_text="Kf1", normalized_text="Kf1", notation_locale="en",
        candidates_json=[{"text": "Kf1", "confidence": 0.99}],
    ))
    assert ocr_input(entry, "tr") == ("Kf1", 0.99)


def test_migration_upgrades_existing_records():
    directory = Path(__file__).parents[1] / "alembic" / "versions"
    with sa.create_engine("sqlite://").begin() as connection:
        with Operations.context(MigrationContext.configure(connection)):
            for index, filename in enumerate(["001_initial_schema.py", "002_review_integrity.py"]):
                spec = importlib.util.spec_from_file_location(f"migration_{index}", directory / filename)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                module.upgrade()
                if index == 0:
                    connection.execute(sa.text("INSERT INTO games (id, session_id, status) VALUES ('g', 'owner', 'completed')"))
            assert connection.execute(sa.text("SELECT session_id FROM games WHERE id='g'")).scalar_one() == "owner"
            inspector = sa.inspect(connection)
            assert {"bbox_x", "bbox_y", "bbox_w", "bbox_h"} <= {c["name"] for c in inspector.get_columns("move_crops")}
            assert next(c for c in inspector.get_columns("games") if c["name"] == "session_id")["type"].length == 64


def test_decompression_bomb_is_rejected():
    from api.routes.upload import _validate_image_dimensions
    with patch("PIL.Image.open", side_effect=Image.DecompressionBombError("too large")):
        assert _validate_image_dimensions(b"fake") is not None


def test_pdf_render_and_multi_page_rejection():
    from services.pdf_renderer import render_pdf, validate_pdf
    image = Image.new("RGB", (200, 300), "white")
    single = io.BytesIO()
    image.save(single, format="PDF")
    validate_pdf(single.getvalue())
    rendered = Image.open(io.BytesIO(render_pdf(single.getvalue())))
    assert rendered.size == (600, 900)
    multi = io.BytesIO()
    image.save(multi, format="PDF", save_all=True, append_images=[image])
    with pytest.raises(ValueError, match="single-page"):
        validate_pdf(multi.getvalue())


@pytest.mark.asyncio
async def test_sse_rechecks_after_subscribe():
    from api.routes.sse import _event_generator
    from tests.test_sse import FakePubSub, FakeRedis
    redis = FakeRedis(FakePubSub([]))
    with patch("api.routes.sse.aioredis.from_url", return_value=redis), \
         patch("api.routes.sse._current_status", AsyncMock(return_value=("completed", None))):
        events = [event async for event in _event_generator("job", "processing", None)]
    assert '"status": "completed"' in events[-1]
    redis.aclose.assert_awaited_once()


def test_production_rejects_default_secret():
    from config import Settings
    with pytest.raises(ValueError, match="SECRET_KEY"):
        Settings(_env_file=None, ENVIRONMENT="production", SECRET_KEY="dev-insecure-change-me")


@pytest.mark.asyncio
async def test_dispatch_failure_marks_game_and_job_failed(app_client, async_session, sample_png_bytes,
                                                        tmp_storage, monkeypatch, mock_celery_task):
    from services import storage
    monkeypatch.setattr(storage, "_storage_instance", storage.LocalStorageBackend(str(tmp_storage)))
    mock_celery_task.apply_async.side_effect = ConnectionError("broker unavailable")
    response = await app_client.post("/api/upload/",
        files={"file": ("sheet.png", sample_png_bytes, "image/png")},
        data={"session_id": "test-session"})
    assert response.status_code == 500
    job = (await async_session.execute(sa.select(ProcessingJob))).scalar_one()
    game = (await async_session.execute(sa.select(Game))).scalar_one()
    assert job.status == game.status == "failed"
    assert job.completed_at is not None


@pytest.mark.asyncio
async def test_completed_job_redelivery_does_not_repeat_ocr(async_session):
    from workers.processing_tasks import _run_pipeline
    game = Game(session_id="test-session", status="needs_review")
    async_session.add(game)
    await async_session.flush()
    job = ProcessingJob(game_id=game.id, status="completed")
    async_session.add(job)
    await async_session.commit()
    with patch("workers.processing_tasks._make_session", return_value=async_session), \
         patch("workers.processing_tasks._load_image", new_callable=AsyncMock) as load:
        result = await _run_pipeline(job_id=job.id, game_id=game.id)
    assert result == {"status": "completed", "skipped": True}
    load.assert_not_called()


@pytest.mark.asyncio
async def test_invalidated_approval_and_legacy_tail_can_be_recovered(async_session, app_client):
    game = await _seed_game(async_session, ["e4", "e5", "Bc4", "Nc6"])
    await correct(app_client, game, 2, "Bc4")
    blocked = await correct(app_client, game, 0, "d4")
    assert len(blocked["moves"]) == 4
    assert blocked["failure_point_ply"] == 2
    assert blocked["moves"][3]["ocr_raw_text"] == "Nc6"
    recovered = await correct(app_client, game, 0, "e4")
    assert [m["selected_san"] for m in recovered["moves"]] == ["e4", "e5", "Bc4", "Nc6"]
    assert not recovered["moves"][2]["needs_manual_review"]


def test_worker_failure_signal_is_connected_to_task_object():
    from celery.signals import task_failure
    from workers.processing_tasks import process_scoresheet_task
    with patch("workers.processing_tasks._make_session", return_value=AsyncMock()), \
         patch("workers.processing_tasks._set_status", new_callable=AsyncMock) as status:
        task_failure.send(sender=process_scoresheet_task, task_id="t",
                          kwargs={"job_id": "j"}, exception=RuntimeError("worker crash"))
    status.assert_awaited_once()
    assert status.call_args.args[1:3] == ("j", "failed")
