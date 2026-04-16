"""
TrOCR OCR provider — primary backend.

Model: microsoft/trocr-large-handwritten
  ~1.2 GB download on first use; cached in HuggingFace cache dir.

Lazy loading
────────────
The model is loaded the first time recognise_batch() is called and kept
alive in module-level singletons for the lifetime of the worker process.
Re-loading on every request would add 5–30 seconds per call.

GPU auto-detection
──────────────────
If torch.cuda.is_available(), the model and all tensors are placed on the
first CUDA device.  On CPU-only machines the inference is slower but correct.

Batch inference
───────────────
All crop images from a single scoresheet are passed in one forward pass
(up to TROCR_MAX_BATCH_SIZE images at a time).  This amortises the
overhead of model.generate() across all moves.

Top-N candidates
────────────────
model.generate() is called with num_beams ≥ TROCR_NUM_CANDIDATES and
num_return_sequences = TROCR_NUM_CANDIDATES.  The raw sequence scores
(cumulative log-probs) are converted to confidences via softmax so they
sum to 1.0 across the N hypotheses for each image.

Installation
────────────
pip install transformers torch Pillow
"""

from __future__ import annotations

import io
import logging
from typing import TYPE_CHECKING, Any, List, Optional, Tuple

import numpy as np

from config import settings
from services.ocr.base import OCRCandidate, OCRPrediction, OCRProvider

if TYPE_CHECKING:
    # These are only imported at runtime inside _load(); here they are just
    # used for type annotations so editors can provide completions.
    from PIL import Image as PILImage

logger = logging.getLogger(__name__)

# ── Module-level lazy singletons ──────────────────────────────────────────────
# Initialised to None; populated on first call to _load().
# Workers share one event loop per process — these are process-local globals,
# not cross-process shared state.

_model: Optional[Any] = None       # VisionEncoderDecoderModel
_processor: Optional[Any] = None   # TrOCRProcessor
_device: Optional[str] = None


# ── Loading ───────────────────────────────────────────────────────────────────

def _load() -> Tuple[Any, Any, str]:
    """
    Load the TrOCR model and processor on first call; return cached on subsequent calls.

    Returns:
        (model, processor, device_string)

    Raises:
        ImportError: If torch or transformers are not installed.
    """
    global _model, _processor, _device

    if _model is not None:
        assert _processor is not None and _device is not None
        return _model, _processor, _device

    # ── Deferred heavy imports ────────────────────────────────────────────────
    try:
        import torch
    except ImportError as exc:
        raise ImportError(
            "torch is required for TrOCR inference but is not installed.\n"
            "Install it with:  pip install torch\n"
            "See https://pytorch.org/get-started/locally/ for platform-specific wheels."
        ) from exc

    try:
        from transformers import TrOCRProcessor, VisionEncoderDecoderModel
    except ImportError as exc:
        raise ImportError(
            "transformers is required for TrOCR inference but is not installed.\n"
            "Install it with:  pip install transformers"
        ) from exc

    try:
        from PIL import Image  # noqa: F401 — verify Pillow is present
    except ImportError as exc:
        raise ImportError(
            "Pillow is required for image pre-processing but is not installed.\n"
            "Install it with:  pip install Pillow"
        ) from exc

    device = "cuda" if torch.cuda.is_available() else "cpu"
    logger.info(
        "Loading TrOCR model '%s' on device='%s'…",
        settings.TROCR_MODEL_ID,
        device,
    )

    processor = TrOCRProcessor.from_pretrained(settings.TROCR_MODEL_ID)
    model = VisionEncoderDecoderModel.from_pretrained(settings.TROCR_MODEL_ID)
    model.to(device)
    model.eval()

    _model, _processor, _device = model, processor, device
    logger.info("TrOCR model loaded successfully.")
    return model, processor, device


# ── Provider ──────────────────────────────────────────────────────────────────

class TrOCRProvider(OCRProvider):
    """
    Primary OCR provider backed by microsoft/trocr-large-handwritten.

    Usage:
        provider = TrOCRProvider()
        results = provider.recognise_batch(list_of_png_bytes)
    """

    @property
    def provider_name(self) -> str:
        return "trocr"

    def recognise_batch(self, images: List[bytes]) -> List[OCRPrediction]:
        """
        Run TrOCR on *images* in batches of TROCR_MAX_BATCH_SIZE.

        Args:
            images: List of PNG/JPEG bytestrings (one per move cell crop).

        Returns:
            List of OCRPrediction, same length and order as *images*.
        """
        if not images:
            raise ValueError("recognise_batch() called with an empty image list.")

        model, processor, device = _load()

        pil_images = [self._bytes_to_pil(b, idx) for idx, b in enumerate(images)]

        results: List[OCRPrediction] = []
        batch_size = settings.TROCR_MAX_BATCH_SIZE

        for start in range(0, len(pil_images), batch_size):
            batch_pil = pil_images[start : start + batch_size]
            batch_results = self._infer_batch(batch_pil, model, processor, device)
            results.extend(batch_results)

        return results

    # ── Internals ─────────────────────────────────────────────────────────────

    @staticmethod
    def _bytes_to_pil(image_bytes: bytes, index: int) -> Any:
        """
        Convert image bytes to a PIL RGB image.

        Never raises — returns a blank 32×32 white image on decode failure
        so that a single corrupt crop doesn't abort the whole batch.
        """
        try:
            from PIL import Image
            img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            return img
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "Failed to decode image at index %d (%s); substituting blank image.",
                index,
                exc,
            )
            from PIL import Image
            return Image.new("RGB", (32, 32), color=(255, 255, 255))

    def _infer_batch(
        self,
        pil_images: List[Any],
        model: Any,
        processor: Any,
        device: str,
    ) -> List[OCRPrediction]:
        """
        Run one forward pass over a list of PIL images.

        Returns a list of OCRPrediction in the same order as *pil_images*.
        """
        import torch

        n_candidates = settings.TROCR_NUM_CANDIDATES
        num_beams = max(n_candidates, 5)  # beams must be ≥ return sequences

        # ── Encode ───────────────────────────────────────────────────────────
        pixel_values = processor(
            images=pil_images, return_tensors="pt"
        ).pixel_values.to(device)

        # ── Generate ─────────────────────────────────────────────────────────
        with torch.no_grad():
            outputs = model.generate(
                pixel_values,
                num_beams=num_beams,
                num_return_sequences=n_candidates,
                output_scores=True,
                return_dict_in_generate=True,
                max_new_tokens=32,  # chess moves are ≤ ~10 chars; 32 is generous
            )

        # outputs.sequences:       [N * n_candidates, seq_len]
        # outputs.sequences_scores: [N * n_candidates]  (cumulative log-probs)
        all_texts: List[str] = processor.batch_decode(
            outputs.sequences, skip_special_tokens=True
        )
        all_scores: np.ndarray = (
            outputs.sequences_scores.cpu().float().numpy()
        )

        # ── Assemble per-image predictions ────────────────────────────────────
        n_images = len(pil_images)
        predictions: List[OCRPrediction] = []

        for i in range(n_images):
            lo = i * n_candidates
            hi = lo + n_candidates
            texts = all_texts[lo:hi]
            scores = all_scores[lo:hi]

            # Softmax over candidate scores → normalised confidences summing to 1
            confidences = _softmax(scores)

            # Sort best-first (model.generate already returns best-first, but
            # be explicit in case the order changes across transformers versions)
            ranked = sorted(
                zip(texts, confidences), key=lambda tc: tc[1], reverse=True
            )
            candidates = [
                OCRCandidate(text=t.strip(), confidence=float(c))
                for t, c in ranked
            ]

            predictions.append(
                OCRPrediction(
                    raw_text=candidates[0].text,
                    candidates=candidates,
                    provider=self.provider_name,
                )
            )

        return predictions


# ── Numeric helpers ───────────────────────────────────────────────────────────

def _softmax(scores: np.ndarray) -> np.ndarray:
    """
    Numerically stable softmax.

    Converts raw log-prob scores into probabilities that sum to 1.
    With a single candidate the result is [1.0].
    """
    shifted = scores - scores.max()
    exp_s = np.exp(shifted)
    return exp_s / exp_s.sum()


# ── Module-level singleton factory ────────────────────────────────────────────

_provider_instance: Optional[TrOCRProvider] = None


def get_trocr_provider() -> TrOCRProvider:
    """
    Return the module-level TrOCRProvider singleton.

    The singleton is created on first call and reused for all subsequent
    calls within the same worker process.  The model itself is lazy-loaded
    inside TrOCRProvider.recognise_batch() on the first inference call.
    """
    global _provider_instance
    if _provider_instance is None:
        _provider_instance = TrOCRProvider()
    return _provider_instance
