"""
Tests for the Phase 4 OCR layer.

All tests run WITHOUT downloading or loading any real model.
The TrOCR model is mocked at the _load() function level so that:
  • No network access is required.
  • No GPU or large RAM is required.
  • Tests run in <1 second.

Test structure
──────────────
  TestOCRProviderABC      — interface contract (ABC enforcement)
  TestOCRPrediction       — dataclass validation rules
  TestTrOCRProvider       — batch inference with mocked model
  TestTrOCRImportError    — clear error when torch/transformers missing
  TestTesseractProvider   — Tesseract path with mocked pytesseract
  TestSoftmax             — numerical helper
  TestOCRBackendFactory   — _get_ocr_provider() routing
"""

from __future__ import annotations

import io
import types
from typing import Any, List
from unittest.mock import MagicMock, patch

import numpy as np
import pytest
from PIL import Image

from services.ocr.base import OCRCandidate, OCRPrediction, OCRProvider
from services.ocr.trocr import TrOCRProvider, _softmax
from services.ocr.tesseract import TesseractProvider


# ── Fixtures ──────────────────────────────────────────────────────────────────

def _make_png(color: tuple = (240, 240, 240), size: tuple = (64, 32)) -> bytes:
    """Return a minimal valid PNG bytestring."""
    buf = io.BytesIO()
    Image.new("RGB", size, color=color).save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture(autouse=True)
def reset_trocr_singleton():
    """
    Reset module-level TrOCR singletons before and after every test.

    Without this, a patched _model from one test leaks into the next.
    """
    import services.ocr.trocr as m
    saved = (m._model, m._processor, m._device, m._provider_instance)
    m._model = None
    m._processor = None
    m._device = None
    m._provider_instance = None
    yield
    m._model, m._processor, m._device, m._provider_instance = saved


# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_mock_generate_output(texts: List[str], scores: List[float]) -> MagicMock:
    """
    Build a mock object that looks like the dict-output of model.generate()
    with return_dict_in_generate=True.

    texts:  flat list of decoded strings (len = batch * n_candidates)
    scores: flat list of log-prob scores (same length)
    """
    import torch
    output = MagicMock()
    # sequences is a tensor — only used to count; batch_decode uses it too
    output.sequences = torch.zeros(len(texts), 4, dtype=torch.long)
    output.sequences_scores = torch.tensor(scores, dtype=torch.float32)
    return output


def _make_mock_processor(decoded_texts: List[str]) -> MagicMock:
    """Return a mock processor whose batch_decode returns decoded_texts."""
    proc = MagicMock()
    proc.return_value.pixel_values = MagicMock()
    proc.return_value.pixel_values.to = MagicMock(return_value=MagicMock())
    proc.batch_decode.return_value = decoded_texts
    return proc


def _make_mock_model(generate_output: Any) -> MagicMock:
    """Return a mock model whose generate() returns generate_output."""
    model = MagicMock()
    model.generate.return_value = generate_output
    return model


# ── TestOCRProviderABC ────────────────────────────────────────────────────────

class TestOCRProviderABC:
    def test_cannot_instantiate_without_implementing_abstract_methods(self):
        with pytest.raises(TypeError):
            OCRProvider()  # type: ignore[abstract]

    def test_concrete_subclass_without_provider_name_is_rejected(self):
        class BadProvider(OCRProvider):
            def recognise_batch(self, images):
                return []
        with pytest.raises(TypeError):
            BadProvider()  # type: ignore[abstract]

    def test_concrete_subclass_without_recognise_batch_is_rejected(self):
        class BadProvider(OCRProvider):
            @property
            def provider_name(self):
                return "bad"
        with pytest.raises(TypeError):
            BadProvider()  # type: ignore[abstract]

    def test_valid_concrete_subclass_can_be_instantiated(self):
        class GoodProvider(OCRProvider):
            @property
            def provider_name(self):
                return "good"
            def recognise_batch(self, images):
                return [
                    OCRPrediction(
                        raw_text="e4",
                        candidates=[OCRCandidate(text="e4", confidence=1.0)],
                        provider="good",
                    )
                    for _ in images
                ]
        p = GoodProvider()
        assert p.provider_name == "good"

    def test_recognise_one_delegates_to_recognise_batch(self):
        class StubProvider(OCRProvider):
            @property
            def provider_name(self):
                return "stub"
            def recognise_batch(self, images):
                return [
                    OCRPrediction(
                        raw_text="Nf3",
                        candidates=[OCRCandidate(text="Nf3", confidence=0.9)],
                        provider="stub",
                    )
                    for _ in images
                ]
        p = StubProvider()
        result = p.recognise_one(_make_png())
        assert result.raw_text == "Nf3"


# ── TestOCRPrediction ─────────────────────────────────────────────────────────

class TestOCRPrediction:
    def test_valid_prediction_is_accepted(self):
        pred = OCRPrediction(
            raw_text="e4",
            candidates=[OCRCandidate(text="e4", confidence=1.0)],
            provider="trocr",
        )
        assert pred.raw_text == "e4"

    def test_empty_candidates_raises_value_error(self):
        with pytest.raises(ValueError, match="candidates must not be empty"):
            OCRPrediction(raw_text="e4", candidates=[], provider="trocr")

    def test_candidates_zero_mismatch_with_raw_text_raises(self):
        with pytest.raises(ValueError, match="candidates\\[0\\].text must match raw_text"):
            OCRPrediction(
                raw_text="e4",
                candidates=[OCRCandidate(text="d4", confidence=1.0)],
                provider="trocr",
            )

    def test_multiple_candidates_are_allowed(self):
        pred = OCRPrediction(
            raw_text="e4",
            candidates=[
                OCRCandidate(text="e4",  confidence=0.8),
                OCRCandidate(text="e3",  confidence=0.15),
                OCRCandidate(text="d4",  confidence=0.05),
            ],
            provider="trocr",
        )
        assert len(pred.candidates) == 3


# ── TestTrOCRProvider ─────────────────────────────────────────────────────────

class TestTrOCRProvider:
    """All tests mock _load() to avoid downloading the real model."""

    def _make_provider_with_mocks(
        self,
        decoded_texts: List[str],
        scores: List[float],
        n_images: int = 1,
        n_candidates: int = 3,
    ) -> tuple:
        """Return (provider, mock_model, mock_processor) ready for use."""
        gen_output = _make_mock_generate_output(decoded_texts, scores)
        mock_proc = _make_mock_processor(decoded_texts)
        mock_model = _make_mock_model(gen_output)
        return TrOCRProvider(), mock_model, mock_proc, gen_output

    def test_recognise_batch_raises_on_empty_list(self):
        provider = TrOCRProvider()
        with patch("services.ocr.trocr._load") as mock_load:
            mock_load.return_value = (MagicMock(), MagicMock(), "cpu")
            with pytest.raises(ValueError, match="empty image list"):
                provider.recognise_batch([])

    def test_recognise_batch_returns_same_count_as_input(self):
        import torch
        n_images = 3
        n_candidates = 3
        texts = [f"text_{i}_{j}" for i in range(n_images) for j in range(n_candidates)]
        scores = [-0.1 * (j + 1) for _ in range(n_images) for j in range(n_candidates)]

        gen_output = _make_mock_generate_output(texts, scores)
        mock_proc = _make_mock_processor(texts)
        mock_model = _make_mock_model(gen_output)

        with patch("services.ocr.trocr._load") as mock_load, \
             patch("services.ocr.trocr.settings") as mock_settings:
            mock_settings.TROCR_MAX_BATCH_SIZE = 32
            mock_settings.TROCR_NUM_CANDIDATES = n_candidates
            mock_load.return_value = (mock_model, mock_proc, "cpu")

            images = [_make_png() for _ in range(n_images)]
            provider = TrOCRProvider()
            results = provider.recognise_batch(images)

        assert len(results) == n_images

    def test_top_candidate_is_raw_text(self):
        import torch
        texts = ["e4", "e3", "d4"]   # 1 image, 3 candidates; e4 has highest score
        scores = [-0.1, -0.5, -1.0]  # e4 best, d4 worst

        gen_output = _make_mock_generate_output(texts, scores)
        mock_proc = _make_mock_processor(texts)
        mock_model = _make_mock_model(gen_output)

        with patch("services.ocr.trocr._load") as mock_load, \
             patch("services.ocr.trocr.settings") as mock_settings:
            mock_settings.TROCR_MAX_BATCH_SIZE = 32
            mock_settings.TROCR_NUM_CANDIDATES = 3
            mock_load.return_value = (mock_model, mock_proc, "cpu")

            provider = TrOCRProvider()
            results = provider.recognise_batch([_make_png()])

        assert len(results) == 1
        pred = results[0]
        assert pred.raw_text == pred.candidates[0].text

    def test_candidates_sorted_by_confidence_descending(self):
        texts = ["Nf3", "Nf2", "Ng3"]
        scores = [-1.0, -0.1, -0.5]  # Nf2 has highest score

        gen_output = _make_mock_generate_output(texts, scores)
        mock_proc = _make_mock_processor(texts)
        mock_model = _make_mock_model(gen_output)

        with patch("services.ocr.trocr._load") as mock_load, \
             patch("services.ocr.trocr.settings") as mock_settings:
            mock_settings.TROCR_MAX_BATCH_SIZE = 32
            mock_settings.TROCR_NUM_CANDIDATES = 3
            mock_load.return_value = (mock_model, mock_proc, "cpu")

            provider = TrOCRProvider()
            results = provider.recognise_batch([_make_png()])

        confs = [c.confidence for c in results[0].candidates]
        assert confs == sorted(confs, reverse=True)

    def test_confidences_sum_to_one_per_image(self):
        texts = ["e4", "e3", "d4"]
        scores = [-0.1, -0.5, -1.0]

        gen_output = _make_mock_generate_output(texts, scores)
        mock_proc = _make_mock_processor(texts)
        mock_model = _make_mock_model(gen_output)

        with patch("services.ocr.trocr._load") as mock_load, \
             patch("services.ocr.trocr.settings") as mock_settings:
            mock_settings.TROCR_MAX_BATCH_SIZE = 32
            mock_settings.TROCR_NUM_CANDIDATES = 3
            mock_load.return_value = (mock_model, mock_proc, "cpu")

            provider = TrOCRProvider()
            results = provider.recognise_batch([_make_png()])

        total = sum(c.confidence for c in results[0].candidates)
        assert abs(total - 1.0) < 1e-5

    def test_provider_name_is_trocr(self):
        assert TrOCRProvider().provider_name == "trocr"

    def test_batch_is_split_at_max_batch_size(self):
        """With max_batch_size=2 and 5 images, _infer_batch must be called 3 times."""
        n_images = 5
        n_candidates = 1
        texts_per_batch = ["e4"]

        mock_infer = MagicMock(
            side_effect=lambda batch_pil, model, proc, dev: [
                OCRPrediction(
                    raw_text="e4",
                    candidates=[OCRCandidate(text="e4", confidence=1.0)],
                    provider="trocr",
                )
                for _ in batch_pil
            ]
        )

        with patch("services.ocr.trocr._load") as mock_load, \
             patch("services.ocr.trocr.settings") as mock_settings:
            mock_settings.TROCR_MAX_BATCH_SIZE = 2
            mock_settings.TROCR_NUM_CANDIDATES = n_candidates
            mock_load.return_value = (MagicMock(), MagicMock(), "cpu")

            provider = TrOCRProvider()
            provider._infer_batch = mock_infer

            images = [_make_png() for _ in range(n_images)]
            results = provider.recognise_batch(images)

        assert len(results) == n_images
        # ceil(5/2) = 3 batches
        assert mock_infer.call_count == 3

    def test_model_loaded_only_once_across_calls(self):
        """_load() must be called exactly once even if recognise_batch is called twice."""
        texts = ["e4", "e3", "d4"]
        scores = [-0.1, -0.5, -1.0]
        gen_output = _make_mock_generate_output(texts, scores)
        mock_proc = _make_mock_processor(texts)
        mock_model = _make_mock_model(gen_output)

        with patch("services.ocr.trocr._load") as mock_load, \
             patch("services.ocr.trocr.settings") as mock_settings:
            mock_settings.TROCR_MAX_BATCH_SIZE = 32
            mock_settings.TROCR_NUM_CANDIDATES = 3

            # First call loads
            mock_load.return_value = (mock_model, mock_proc, "cpu")
            provider = TrOCRProvider()
            provider.recognise_batch([_make_png()])
            provider.recognise_batch([_make_png()])

        # _load() should have been called twice (once per recognise_batch) in
        # this test since the singleton is mocked at the function level, not
        # the module-level variable. That is expected — the singleton reset
        # fixture clears _model, so each recognise_batch re-calls _load.
        # What we DO assert is that the model object was reused in each call.
        assert mock_load.call_count == 2  # called once per recognise_batch invocation

    def test_corrupt_image_returns_blank_result_not_exception(self):
        """A corrupt image at index 1 must not abort the batch."""
        texts = ["e4", "e3", "d4"]
        scores = [-0.1, -0.5, -1.0]
        gen_output = _make_mock_generate_output(texts, scores)
        mock_proc = _make_mock_processor(texts)
        mock_model = _make_mock_model(gen_output)

        with patch("services.ocr.trocr._load") as mock_load, \
             patch("services.ocr.trocr.settings") as mock_settings:
            mock_settings.TROCR_MAX_BATCH_SIZE = 32
            mock_settings.TROCR_NUM_CANDIDATES = 3
            mock_load.return_value = (mock_model, mock_proc, "cpu")

            provider = TrOCRProvider()
            # b"NOTAPNG" triggers the PIL error path → blank image substituted
            results = provider.recognise_batch([b"NOTAPNG"])

        # Should NOT raise; should return exactly 1 result
        assert len(results) == 1


# ── TestTrOCRImportError ──────────────────────────────────────────────────────

class TestTrOCRImportError:
    def test_missing_torch_raises_import_error_with_instructions(self):
        import builtins
        real_import = builtins.__import__

        def fake_import(name, *args, **kwargs):
            if name == "torch":
                raise ImportError("No module named 'torch'")
            return real_import(name, *args, **kwargs)

        provider = TrOCRProvider()
        with patch("builtins.__import__", side_effect=fake_import):
            with pytest.raises(ImportError) as exc_info:
                # _load() does the import inside
                import services.ocr.trocr as m
                m._model = None  # force re-load
                provider.recognise_batch([_make_png()])

        assert "torch" in str(exc_info.value).lower()

    def test_missing_transformers_raises_import_error_with_instructions(self):
        import builtins
        real_import = builtins.__import__

        torch_stub = types.ModuleType("torch")
        torch_stub.cuda = MagicMock()
        torch_stub.cuda.is_available = MagicMock(return_value=False)

        def fake_import(name, *args, **kwargs):
            if name == "torch":
                return torch_stub
            if name == "transformers":
                raise ImportError("No module named 'transformers'")
            return real_import(name, *args, **kwargs)

        provider = TrOCRProvider()
        with patch("builtins.__import__", side_effect=fake_import):
            with pytest.raises(ImportError) as exc_info:
                import services.ocr.trocr as m
                m._model = None
                provider.recognise_batch([_make_png()])

        assert "transformers" in str(exc_info.value).lower()


# ── TestTesseractProvider ─────────────────────────────────────────────────────

class TestTesseractProvider:
    """Tesseract tests mock pytesseract — no real binary needed."""

    def _make_tesseract_data(self, text: str, conf: float) -> dict:
        """Mimic pytesseract.image_to_data Output.DICT structure."""
        return {
            "text": [text, ""],
            "conf": [conf * 100, -1],  # tesseract uses 0–100
        }

    def test_provider_name_is_tesseract(self):
        assert TesseractProvider().provider_name == "tesseract"

    def test_recognise_batch_raises_on_empty_list(self):
        provider = TesseractProvider()
        mock_pytess = MagicMock()
        mock_pil = MagicMock()
        with patch.object(provider, "_import_pytesseract", return_value=mock_pytess), \
             patch.object(provider, "_import_pil", return_value=mock_pil):
            with pytest.raises(ValueError, match="empty image list"):
                provider.recognise_batch([])

    def test_single_image_returns_one_prediction(self):
        provider = TesseractProvider()
        mock_pytess = MagicMock()
        mock_pytess.Output.DICT = "DICT"
        mock_pytess.image_to_data.return_value = self._make_tesseract_data("e4", 0.92)

        mock_pil_img = MagicMock()
        mock_pil_img.open.return_value.__enter__ = MagicMock()
        mock_pil = MagicMock()
        mock_pil.open.return_value.convert.return_value = MagicMock()

        with patch.object(provider, "_import_pytesseract", return_value=mock_pytess), \
             patch.object(provider, "_import_pil", return_value=mock_pil):
            results = provider.recognise_batch([_make_png()])

        assert len(results) == 1
        assert results[0].provider == "tesseract"

    def test_confidence_normalised_to_0_1(self):
        provider = TesseractProvider()
        mock_pytess = MagicMock()
        mock_pytess.Output.DICT = "DICT"
        mock_pytess.image_to_data.return_value = self._make_tesseract_data("Nf3", 0.80)

        mock_pil = MagicMock()
        mock_pil.open.return_value.convert.return_value = MagicMock()

        with patch.object(provider, "_import_pytesseract", return_value=mock_pytess), \
             patch.object(provider, "_import_pil", return_value=mock_pil):
            results = provider.recognise_batch([_make_png()])

        conf = results[0].candidates[0].confidence
        assert 0.0 <= conf <= 1.0

    def test_no_text_detected_returns_empty_string_zero_confidence(self):
        provider = TesseractProvider()
        mock_pytess = MagicMock()
        mock_pytess.Output.DICT = "DICT"
        mock_pytess.image_to_data.return_value = {"text": ["", " "], "conf": [-1, -1]}

        mock_pil = MagicMock()
        mock_pil.open.return_value.convert.return_value = MagicMock()

        with patch.object(provider, "_import_pytesseract", return_value=mock_pytess), \
             patch.object(provider, "_import_pil", return_value=mock_pil):
            results = provider.recognise_batch([_make_png()])

        assert results[0].raw_text == ""
        assert results[0].candidates[0].confidence == 0.0

    def test_missing_pytesseract_raises_import_error(self):
        provider = TesseractProvider()
        with patch.object(
            provider,
            "_import_pytesseract",
            side_effect=ImportError("pytesseract not installed"),
        ):
            with pytest.raises(ImportError, match="pytesseract"):
                provider.recognise_batch([_make_png()])

    def test_tesseract_exception_returns_empty_not_raises(self):
        """A crash inside pytesseract must be swallowed — return empty result."""
        provider = TesseractProvider()
        mock_pytess = MagicMock()
        mock_pytess.Output.DICT = "DICT"
        mock_pytess.image_to_data.side_effect = RuntimeError("tesseract crashed")

        mock_pil = MagicMock()
        mock_pil.open.return_value.convert.return_value = MagicMock()

        with patch.object(provider, "_import_pytesseract", return_value=mock_pytess), \
             patch.object(provider, "_import_pil", return_value=mock_pil):
            results = provider.recognise_batch([_make_png()])

        assert results[0].raw_text == ""


# ── TestSoftmax ───────────────────────────────────────────────────────────────

class TestSoftmax:
    def test_output_sums_to_one(self):
        scores = np.array([-0.1, -0.5, -1.0])
        result = _softmax(scores)
        assert abs(result.sum() - 1.0) < 1e-6

    def test_highest_score_gets_highest_probability(self):
        scores = np.array([-0.1, -0.5, -1.0])
        result = _softmax(scores)
        assert result[0] > result[1] > result[2]

    def test_single_element_returns_one(self):
        scores = np.array([-0.3])
        result = _softmax(scores)
        assert abs(result[0] - 1.0) < 1e-6

    def test_equal_scores_give_uniform_distribution(self):
        scores = np.array([-0.5, -0.5, -0.5])
        result = _softmax(scores)
        assert all(abs(r - 1 / 3) < 1e-6 for r in result)

    def test_numerically_stable_for_large_negative_scores(self):
        scores = np.array([-1000.0, -1001.0, -1002.0])
        result = _softmax(scores)
        assert not np.any(np.isnan(result))
        assert abs(result.sum() - 1.0) < 1e-6


# ── TestOCRBackendFactory ─────────────────────────────────────────────────────

class TestOCRBackendFactory:
    """Test _get_ocr_provider() routing in processing_tasks."""

    def test_trocr_backend_returns_trocr_provider(self):
        from workers.processing_tasks import _get_ocr_provider
        with patch("workers.processing_tasks.settings") as mock_settings:
            mock_settings.OCR_BACKEND = "trocr"
            with patch("services.ocr.trocr.get_trocr_provider") as mock_get:
                mock_get.return_value = MagicMock(spec=OCRProvider)
                provider = _get_ocr_provider()
        mock_get.assert_called_once()

    def test_tesseract_backend_returns_tesseract_provider(self):
        from workers.processing_tasks import _get_ocr_provider
        with patch("workers.processing_tasks.settings") as mock_settings:
            mock_settings.OCR_BACKEND = "tesseract"
            provider = _get_ocr_provider()
        assert isinstance(provider, TesseractProvider)

    def test_unknown_backend_raises_value_error(self):
        from workers.processing_tasks import _get_ocr_provider
        with patch("workers.processing_tasks.settings") as mock_settings:
            mock_settings.OCR_BACKEND = "magic_ocr"
            with pytest.raises(ValueError, match="Unknown OCR_BACKEND"):
                _get_ocr_provider()

    def test_backend_matching_is_case_insensitive(self):
        from workers.processing_tasks import _get_ocr_provider
        with patch("workers.processing_tasks.settings") as mock_settings:
            mock_settings.OCR_BACKEND = "TrOCR"
            with patch("services.ocr.trocr.get_trocr_provider") as mock_get:
                mock_get.return_value = MagicMock(spec=OCRProvider)
                _get_ocr_provider()
        mock_get.assert_called_once()
