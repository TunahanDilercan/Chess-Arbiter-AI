"""
Move cell crop extraction from a preprocessed scoresheet image.

Responsibilities
────────────────
• Iterate every (row, column) cell in the GridLayout.
• Detect blank cells (empty move slots) by white-pixel fraction of the
  inner cell area.  Blank cells → no crop, no MoveEntry.
• Assign correct ply_index and move_number to each non-blank cell.
• Encode each cell as a PNG bytestring (lossless, suitable for TrOCR).
• Return a list of CropResult objects ready for DB persistence (MoveCrop).

Blank detection
───────────────
The outer 3 pixels of each cell are excluded to avoid counting grid line
pixels as "ink".  A cell is blank when the fraction of white (background)
pixels in the inner region exceeds CV_BLANK_CELL_THRESHOLD (default 0.97).

Ply index mapping
──────────────────
  single_table:
    row k, white column → ply_index = 2k
    row k, black column → ply_index = 2k + 1

  double_table:
    left group,  row k → same as single_table
    right group, row k → ply_index = 2*(num_rows + k)  [white]
                          ply_index = 2*(num_rows + k) + 1  [black]
"""

from __future__ import annotations

import io
import logging
from dataclasses import dataclass
from typing import List, Literal, Optional, Tuple

import cv2
import numpy as np

from config import settings
from services.cv.grid_detector import ColumnGroup, GridLayout

logger = logging.getLogger(__name__)

# Border to exclude from blank detection (pixels)
_BORDER: int = 3


# ── Result type ───────────────────────────────────────────────────────────────

@dataclass
class CropResult:
    """
    One extracted move cell, ready for DB storage as a MoveCrop record.

    Fields
    ──────
    ply_index     — 0-based half-move index within the game.
    move_number   — 1-based full-move number shown on the scoresheet.
    color         — "white" | "black"
    image_bytes   — PNG-encoded cell image (lossless).
    is_blank      — True → cell was empty; image_bytes may still be present
                    but no MoveEntry should be created.
    source_region — (x1, y1, x2, y2) in the original image coordinates.
    section_index — 0 for the main (or only) table, 1 for the right table
                    in a double_table layout.
    """
    ply_index: int
    move_number: int
    color: Literal["white", "black"]
    image_bytes: bytes
    is_blank: bool
    source_region: Tuple[int, int, int, int]  # (x1, y1, x2, y2)
    section_index: int


# ── Extractor ─────────────────────────────────────────────────────────────────

class CropExtractor:
    """
    Slice a preprocessed grayscale image into individual move cells
    according to a GridLayout detected by GridDetector.

    Args:
        gray:   Grayscale image array (uint8) from ImagePreprocessor.
        binary: Binary image (ink=255, bg=0) from ImagePreprocessor.
                Used for blank detection only.
        layout: GridLayout from GridDetector.detect().
    """

    def __init__(
        self,
        gray: np.ndarray,
        binary: np.ndarray,
        layout: GridLayout,
    ) -> None:
        self._gray = gray
        self._binary = binary
        self._layout = layout
        self._h, self._w = gray.shape

    def extract(self) -> List[CropResult]:
        """
        Extract all non-blank move cells.

        Returns:
            List of CropResult sorted by ply_index ascending.
            Blank cells are included with is_blank=True so callers can
            distinguish "skipped" from "never reached".
        """
        results: List[CropResult] = []
        num_rows = len(self._layout.row_boundaries)

        for section_idx, group in enumerate(self._layout.column_groups):
            base_ply_offset = section_idx * num_rows * 2

            for row_idx, (y_top, y_bottom) in enumerate(self._layout.row_boundaries):
                move_number = row_idx + 1  # 1-based

                for color, bounds in (
                    ("white", group.white),
                    ("black", group.black),
                ):
                    color_offset = 0 if color == "white" else 1
                    ply_index = base_ply_offset + row_idx * 2 + color_offset

                    x1, x2 = bounds
                    crop = self._slice(x1, x2, y_top, y_bottom)

                    is_blank = self._is_blank(crop)
                    img_bytes = self._encode_png(crop)

                    results.append(
                        CropResult(
                            ply_index=ply_index,
                            move_number=move_number,
                            color=color,  # type: ignore[arg-type]
                            image_bytes=img_bytes,
                            is_blank=is_blank,
                            source_region=(x1, y_top, x2, y_bottom),
                            section_index=section_idx,
                        )
                    )

        results.sort(key=lambda r: r.ply_index)
        non_blank = sum(1 for r in results if not r.is_blank)
        logger.info(
            "Extracted %d cells (%d non-blank) from %s layout",
            len(results),
            non_blank,
            self._layout.detected_format,
        )
        return results

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _slice(self, x1: int, x2: int, y1: int, y2: int) -> np.ndarray:
        """Slice the grayscale image, clamped to image bounds."""
        y1 = max(0, y1)
        y2 = min(self._h, y2)
        x1 = max(0, x1)
        x2 = min(self._w, x2)
        return self._gray[y1:y2, x1:x2]

    def _is_blank(self, crop: np.ndarray) -> bool:
        """
        Return True if the inner cell region is predominantly white (background).

        We exclude _BORDER pixels around the edge to avoid counting grid lines.
        A fraction above CV_BLANK_CELL_THRESHOLD (default 0.97) → blank.
        """
        h, w = crop.shape
        if h <= 2 * _BORDER or w <= 2 * _BORDER:
            # Cell too small to measure reliably → assume blank
            return True

        inner = crop[_BORDER : h - _BORDER, _BORDER : w - _BORDER]
        total_pixels = inner.size
        if total_pixels == 0:
            return True

        # In the grayscale image, background is light (high value).
        # Threshold at 200 to call a pixel "white / background".
        white_pixels = int(np.sum(inner > 200))
        fraction = white_pixels / total_pixels

        return fraction > settings.CV_BLANK_CELL_THRESHOLD

    @staticmethod
    def _encode_png(crop: np.ndarray) -> bytes:
        """Encode a numpy array as a PNG bytestring."""
        ok, buf = cv2.imencode(".png", crop)
        if not ok or buf is None:
            raise RuntimeError("cv2.imencode failed — cannot encode cell crop as PNG.")
        return bytes(buf)
