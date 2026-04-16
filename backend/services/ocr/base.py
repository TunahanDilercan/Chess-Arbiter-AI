"""
Abstract OCR provider interface.

ALL OCR access must go through OCRProvider.recognise_batch().
Never instantiate TrOCR or Tesseract directly in routes or tasks.

Design choices
──────────────
• Batch-first API: recognise_batch() takes a list of images and returns a
  list of OCRPrediction in the same order.  This lets providers use
  efficient batched forward passes (TrOCR) or per-image calls (Tesseract).

• OCRPrediction is intentionally distinct from the ORM model OCRResult
  (models/game.py).  The prediction is the raw provider output; persistence
  is the caller's responsibility.

• provider_name is a plain string so it can be stored in OCRResult rows
  without an enum dependency.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import List


@dataclass(frozen=True)
class OCRCandidate:
    """
    One hypothesis from an OCR provider for a single move cell.

    text       — recognised text string (may be empty if cell is blank/unreadable)
    confidence — normalised score in [0.0, 1.0]; higher = more confident
    """
    text: str
    confidence: float


@dataclass(frozen=True)
class OCRPrediction:
    """
    Full OCR result for one move cell image.

    raw_text   — top-1 hypothesis (highest confidence candidate)
    candidates — top-N hypotheses ordered by confidence descending,
                 always includes the top-1 as candidates[0]
    provider   — backend identifier: "trocr" | "tesseract"
    """
    raw_text: str
    candidates: List[OCRCandidate]
    provider: str

    def __post_init__(self) -> None:
        if not self.candidates:
            raise ValueError("OCRPrediction.candidates must not be empty.")
        if self.candidates[0].text != self.raw_text:
            raise ValueError(
                "candidates[0].text must match raw_text "
                f"(got {self.candidates[0].text!r} vs {self.raw_text!r})."
            )


class OCRProvider(ABC):
    """
    Abstract base class for OCR backends.

    Implementations
    ───────────────
      TrOCRProvider    — primary; microsoft/trocr-large-handwritten
      TesseractProvider — dev/comparison only
    """

    @property
    @abstractmethod
    def provider_name(self) -> str:
        """Short identifier string stored in OCRResult rows."""

    @abstractmethod
    def recognise_batch(self, images: List[bytes]) -> List[OCRPrediction]:
        """
        Run OCR on a batch of cell images.

        Args:
            images: Non-empty list of PNG or JPEG bytestrings.
                    Each element is one move cell crop.

        Returns:
            List of OCRPrediction, same length and order as *images*.
            Never raises for a single bad image — instead returns an
            OCRPrediction with empty text and zero confidence for that slot.

        Raises:
            ValueError: If *images* is empty.
        """

    # ── Convenience ───────────────────────────────────────────────────────────

    def recognise_one(self, image: bytes) -> OCRPrediction:
        """Convenience wrapper around recognise_batch for a single image."""
        results = self.recognise_batch([image])
        return results[0]
