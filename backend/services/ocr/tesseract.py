"""
Tesseract OCR provider.

⚠  DEV / COMPARISON ONLY — NOT FOR PRODUCTION USE ⚠
─────────────────────────────────────────────────────
Tesseract is a printed-text OCR engine.  It performs poorly on handwritten
chess notation.  This provider exists solely for:
  • Quick local smoke-testing without downloading the TrOCR model
  • Side-by-side accuracy comparison with TrOCR during development

NEVER use TesseractProvider as the OCR_BACKEND in a deployed environment.
The production backend must always be TrOCRProvider.

Installation:
    1. Install the Tesseract binary:
         macOS:   brew install tesseract
         Ubuntu:  apt-get install tesseract-ocr
         Windows: https://github.com/UB-Mannheim/tesseract/wiki
    2. Install the Python wrapper:
         pip install pytesseract
"""

from __future__ import annotations

import io
import logging
from typing import Any, List

from services.ocr.base import OCRCandidate, OCRPrediction, OCRProvider

logger = logging.getLogger(__name__)

# Tesseract PSM 8 = single word, suitable for individual move cells.
_TESSERACT_CONFIG = "--psm 8 -c tessedit_char_whitelist=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789=#+-x/"


class TesseractProvider(OCRProvider):
    """
    ⚠  DEV / COMPARISON ONLY ⚠

    OCR provider backed by Tesseract.  Implements the same OCRProvider
    interface as TrOCRProvider so it can be swapped in for local testing
    by setting OCR_BACKEND=tesseract in the environment.

    Tesseract does not support beam-search candidates; each image produces
    exactly one hypothesis.  The confidence is taken from Tesseract's
    internal word confidence score (0–100 → normalised to 0.0–1.0).
    If no text is detected the candidate has confidence 0.0 and empty text.
    """

    @property
    def provider_name(self) -> str:
        return "tesseract"

    def recognise_batch(self, images: List[bytes]) -> List[OCRPrediction]:
        """
        Run Tesseract on each image individually (no true batching).

        Args:
            images: List of PNG/JPEG bytestrings.

        Returns:
            List of OCRPrediction with exactly one candidate per image.
        """
        if not images:
            raise ValueError("recognise_batch() called with an empty image list.")

        pytesseract = self._import_pytesseract()
        PIL_Image = self._import_pil()

        results: List[OCRPrediction] = []
        for idx, img_bytes in enumerate(images):
            prediction = self._recognise_one(img_bytes, idx, pytesseract, PIL_Image)
            results.append(prediction)
        return results

    # ── Internals ─────────────────────────────────────────────────────────────

    @staticmethod
    def _recognise_one(
        image_bytes: bytes,
        index: int,
        pytesseract: Any,
        PIL_Image: Any,
    ) -> OCRPrediction:
        """Recognise a single image; return a safe fallback on any error."""
        try:
            img = PIL_Image.open(io.BytesIO(image_bytes)).convert("RGB")
            data = pytesseract.image_to_data(
                img,
                config=_TESSERACT_CONFIG,
                output_type=pytesseract.Output.DICT,
            )
            # Filter to words with confidence > 0
            words = [
                (str(data["text"][i]), float(data["conf"][i]))
                for i in range(len(data["text"]))
                if str(data["text"][i]).strip()
                and float(data["conf"][i]) > 0
            ]

            if words:
                # Join all detected words (shouldn't be more than one for a cell)
                text = " ".join(w for w, _ in words).strip()
                # Average confidence, normalised from [0,100] to [0,1]
                avg_conf = sum(c for _, c in words) / len(words) / 100.0
            else:
                text = ""
                avg_conf = 0.0

        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "Tesseract failed on image at index %d (%s); returning empty result.",
                index,
                exc,
            )
            text = ""
            avg_conf = 0.0

        candidate = OCRCandidate(text=text, confidence=avg_conf)
        return OCRPrediction(
            raw_text=text,
            candidates=[candidate],
            provider="tesseract",
        )

    @staticmethod
    def _import_pytesseract() -> Any:
        try:
            import pytesseract
            return pytesseract
        except ImportError as exc:
            raise ImportError(
                "pytesseract is required for the Tesseract OCR backend "
                "but is not installed.\n"
                "Install it with:  pip install pytesseract\n"
                "You also need the Tesseract binary — see the module docstring."
            ) from exc

    @staticmethod
    def _import_pil() -> Any:
        try:
            from PIL import Image
            return Image
        except ImportError as exc:
            raise ImportError(
                "Pillow is required but is not installed.\n"
                "Install it with:  pip install Pillow"
            ) from exc
