"""
Tests for the Claude Vision OCR provider (services/ocr/claude_vision.py).

All API access is mocked — no network calls, no API key required.
"""

from __future__ import annotations

import io
import json
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

import services.ocr.claude_vision as cv
from services.ocr.claude_vision import (
    ClaudeVisionError,
    ClaudeVisionProvider,
    SheetMove,
    blank_prediction,
    parse_sheet_payload,
    sheet_move_to_prediction,
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _png_bytes(width: int = 64, height: int = 64) -> bytes:
    buf = io.BytesIO()
    Image.new("L", (width, height), color=255).save(buf, format="PNG")
    return buf.getvalue()


def _mock_response(payload: dict) -> SimpleNamespace:
    """Build a fake anthropic Message with one text block of JSON."""
    block = SimpleNamespace(type="text", text=json.dumps(payload))
    usage = SimpleNamespace(input_tokens=1000, output_tokens=200)
    return SimpleNamespace(content=[block], usage=usage)


@pytest.fixture
def mock_client():
    """Patch the module-level client cache with a MagicMock."""
    client = MagicMock()
    with patch.object(cv, "_client", client):
        yield client


# ── SheetMove ─────────────────────────────────────────────────────────────────

class TestSheetMove:
    def test_ply_index_white(self):
        assert SheetMove(1, "white", "e4", 0.9).ply_index == 0

    def test_ply_index_black(self):
        assert SheetMove(1, "black", "e5", 0.9).ply_index == 1

    def test_ply_index_later_move(self):
        assert SheetMove(13, "black", "Qxd5", 0.9).ply_index == 25


# ── parse_sheet_payload ───────────────────────────────────────────────────────

class TestParseSheetPayload:
    def test_valid_moves_sorted_by_ply(self):
        payload = {
            "moves": [
                {"move_number": 2, "color": "white", "text": "Nf3", "confidence": 0.9, "alternates": []},
                {"move_number": 1, "color": "black", "text": "e5", "confidence": 0.95, "alternates": []},
                {"move_number": 1, "color": "white", "text": "e4", "confidence": 0.99, "alternates": []},
            ],
            "result_notation": None,
        }
        moves = parse_sheet_payload(payload)
        assert [m.text for m in moves] == ["e4", "e5", "Nf3"]
        assert [m.ply_index for m in moves] == [0, 1, 2]

    def test_invalid_entries_dropped(self):
        payload = {
            "moves": [
                {"move_number": 0, "color": "white", "text": "e4", "confidence": 0.9, "alternates": []},
                {"move_number": 1, "color": "purple", "text": "e4", "confidence": 0.9, "alternates": []},
                {"move_number": 1, "color": "white", "text": "", "confidence": 0.9, "alternates": []},
                {"move_number": 1, "color": "white", "text": "e4", "confidence": 0.9, "alternates": []},
            ],
        }
        moves = parse_sheet_payload(payload)
        assert len(moves) == 1
        assert moves[0].text == "e4"

    def test_duplicate_cell_keeps_higher_confidence(self):
        payload = {
            "moves": [
                {"move_number": 1, "color": "white", "text": "e4", "confidence": 0.5, "alternates": []},
                {"move_number": 1, "color": "white", "text": "d4", "confidence": 0.8, "alternates": []},
            ],
        }
        moves = parse_sheet_payload(payload)
        assert len(moves) == 1
        assert moves[0].text == "d4"

    def test_confidence_clamped(self):
        payload = {
            "moves": [
                {"move_number": 1, "color": "white", "text": "e4", "confidence": 1.7, "alternates": []},
                {"move_number": 1, "color": "black", "text": "e5", "confidence": -0.2, "alternates": []},
            ],
        }
        moves = parse_sheet_payload(payload)
        assert moves[0].confidence == 1.0
        assert moves[1].confidence == 0.0

    def test_alternates_capped_at_three(self):
        payload = {
            "moves": [
                {"move_number": 1, "color": "white", "text": "Nc3",
                 "confidence": 0.6, "alternates": ["Ne3", "Nb3", "Na3", "Nd3"]},
            ],
        }
        moves = parse_sheet_payload(payload)
        assert moves[0].alternates == ("Ne3", "Nb3", "Na3")


# ── sheet_move_to_prediction ──────────────────────────────────────────────────

class TestSheetMoveToPrediction:
    def test_top_candidate_is_raw_text(self):
        move = SheetMove(1, "white", "e4", 0.9)
        pred = sheet_move_to_prediction(move, "claude_vision")
        assert pred.raw_text == "e4"
        assert pred.candidates[0].text == "e4"
        assert pred.candidates[0].confidence == 0.9
        assert pred.provider == "claude_vision"

    def test_alternates_share_residual_mass_descending(self):
        move = SheetMove(1, "white", "Nc3", 0.6, alternates=("Ne3", "Nb3"))
        pred = sheet_move_to_prediction(move, "claude_vision")
        confs = [c.confidence for c in pred.candidates]
        assert confs == sorted(confs, reverse=True)
        # Residual 0.4 split 2:1 between two alternates.
        assert confs[1] == pytest.approx(0.4 * 2 / 3)
        assert confs[2] == pytest.approx(0.4 * 1 / 3)

    def test_blank_prediction_contract(self):
        pred = blank_prediction("claude_vision")
        assert pred.raw_text == ""
        assert pred.candidates[0].confidence == 0.0


# ── recognise_sheet ───────────────────────────────────────────────────────────

class TestRecogniseSheet:
    def test_returns_parsed_moves(self, mock_client):
        mock_client.messages.create.return_value = _mock_response({
            "moves": [
                {"move_number": 1, "color": "white", "text": "e4", "confidence": 0.98, "alternates": []},
                {"move_number": 1, "color": "black", "text": "c5", "confidence": 0.92, "alternates": []},
            ],
            "result_notation": "1-0",
        })
        moves = ClaudeVisionProvider().recognise_sheet(_png_bytes())
        assert [m.text for m in moves] == ["e4", "c5"]

    def test_sends_image_and_schema(self, mock_client):
        mock_client.messages.create.return_value = _mock_response({"moves": [], "result_notation": None})
        ClaudeVisionProvider().recognise_sheet(_png_bytes())
        kwargs = mock_client.messages.create.call_args.kwargs
        content = kwargs["messages"][0]["content"]
        assert content[0]["type"] == "image"
        assert content[0]["source"]["type"] == "base64"
        assert kwargs["output_config"]["format"]["type"] == "json_schema"

    def test_large_image_downscaled(self, mock_client):
        import base64
        mock_client.messages.create.return_value = _mock_response({"moves": [], "result_notation": None})
        ClaudeVisionProvider().recognise_sheet(_png_bytes(4000, 3000))
        content = mock_client.messages.create.call_args.kwargs["messages"][0]["content"]
        sent = Image.open(io.BytesIO(base64.standard_b64decode(content[0]["source"]["data"])))
        assert max(sent.size) <= 2576

    def test_api_error_wrapped(self, mock_client):
        mock_client.messages.create.side_effect = RuntimeError("boom")
        with pytest.raises(ClaudeVisionError, match="API call failed"):
            ClaudeVisionProvider().recognise_sheet(_png_bytes())

    def test_invalid_json_raises(self, mock_client):
        block = SimpleNamespace(type="text", text="not json {")
        mock_client.messages.create.return_value = SimpleNamespace(
            content=[block], usage=SimpleNamespace(input_tokens=0, output_tokens=0)
        )
        with pytest.raises(ClaudeVisionError, match="invalid JSON"):
            ClaudeVisionProvider().recognise_sheet(_png_bytes())

    def test_undecodable_image_raises(self, mock_client):
        with pytest.raises(ClaudeVisionError, match="Cannot decode"):
            ClaudeVisionProvider().recognise_sheet(b"not an image")

    def test_thinking_block_before_text_is_skipped(self, mock_client):
        thinking = SimpleNamespace(type="thinking", thinking="")
        text = SimpleNamespace(
            type="text", text=json.dumps({"moves": [], "result_notation": None})
        )
        mock_client.messages.create.return_value = SimpleNamespace(
            content=[thinking, text],
            usage=SimpleNamespace(input_tokens=0, output_tokens=0),
        )
        assert ClaudeVisionProvider().recognise_sheet(_png_bytes()) == []


# ── recognise_batch ───────────────────────────────────────────────────────────

class TestRecogniseBatch:
    def test_empty_list_raises_value_error(self):
        with pytest.raises(ValueError):
            ClaudeVisionProvider().recognise_batch([])

    def test_predictions_aligned_by_image_index(self, mock_client):
        mock_client.messages.create.return_value = _mock_response({
            "readings": [
                {"image_index": 1, "text": "e5", "confidence": 0.9, "alternates": []},
                {"image_index": 0, "text": "e4", "confidence": 0.95, "alternates": []},
            ],
        })
        preds = ClaudeVisionProvider().recognise_batch([_png_bytes(), _png_bytes()])
        assert [p.raw_text for p in preds] == ["e4", "e5"]

    def test_missing_index_becomes_blank(self, mock_client):
        mock_client.messages.create.return_value = _mock_response({
            "readings": [
                {"image_index": 0, "text": "e4", "confidence": 0.95, "alternates": []},
            ],
        })
        preds = ClaudeVisionProvider().recognise_batch([_png_bytes(), _png_bytes()])
        assert preds[1].raw_text == ""
        assert preds[1].candidates[0].confidence == 0.0

    def test_corrupt_image_becomes_blank_not_exception(self, mock_client):
        mock_client.messages.create.return_value = _mock_response({
            "readings": [
                {"image_index": 0, "text": "??", "confidence": 0.4, "alternates": []},
                {"image_index": 1, "text": "e5", "confidence": 0.9, "alternates": []},
            ],
        })
        preds = ClaudeVisionProvider().recognise_batch([b"corrupt", _png_bytes()])
        assert preds[0].raw_text == ""        # undecodable → forced blank
        assert preds[1].raw_text == "e5"

    def test_chunking_splits_large_batches(self, mock_client):
        mock_client.messages.create.return_value = _mock_response({"readings": []})
        n = ClaudeVisionProvider.BATCH_CHUNK_SIZE + 5
        preds = ClaudeVisionProvider().recognise_batch([_png_bytes()] * n)
        assert len(preds) == n
        assert mock_client.messages.create.call_count == 2


# ── Pipeline factory routing ──────────────────────────────────────────────────

class TestFactoryRouting:
    def test_claude_backend_returns_claude_provider(self):
        from workers.processing_tasks import _get_ocr_provider
        with patch("workers.processing_tasks.settings") as mock_settings:
            mock_settings.OCR_BACKEND = "claude"
            provider = _get_ocr_provider()
        assert provider.provider_name == "claude_vision"

    def test_allow_claude_false_falls_back_to_trocr(self):
        from workers.processing_tasks import _get_ocr_provider
        with patch("workers.processing_tasks.settings") as mock_settings:
            mock_settings.OCR_BACKEND = "claude"
            with patch("services.ocr.trocr.get_trocr_provider") as mock_factory:
                mock_factory.return_value = MagicMock(provider_name="trocr")
                provider = _get_ocr_provider(allow_claude=False)
        assert provider.provider_name == "trocr"
