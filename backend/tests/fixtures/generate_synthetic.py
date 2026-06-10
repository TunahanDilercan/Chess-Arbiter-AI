"""
Synthetic scoresheet image generator for CV pipeline tests.

Generates realistic-looking chess scoresheet images using PIL so that
tests don't require real photographs or large binary fixtures.

Classes
───────
    SyntheticScoresheet — generates PIL images and returns them as bytes

Supported quality levels
─────────────────────────
    clean  — sharp lines, clear text → should always pass detection
    messy  — slight rotation, added noise → should still pass with margins
    faded  — low contrast lines → may trigger LowConfidenceError (for negative tests)
"""

from __future__ import annotations

import io
import math
import random
from dataclasses import dataclass, field
from typing import List, Literal, Optional, Tuple

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ── Constants ─────────────────────────────────────────────────────────────────

# Default image size matches a typical phone photo at medium resolution.
DEFAULT_WIDTH: int = 800
DEFAULT_HEIGHT: int = 1050

# Margin around the grid
MARGIN_LEFT: int = 40
MARGIN_TOP: int = 60
MARGIN_RIGHT: int = 40
MARGIN_BOTTOM: int = 40

# Column proportions (relative widths summing to 1.0)
# move_no : white : black
COLUMN_RATIOS: Tuple[float, float, float] = (0.12, 0.44, 0.44)

# Quality levels → (noise_sigma, rotation_deg, line_color)
# line_color is the pixel value of ink lines: lower = darker = more contrast.
# Background is 245, so:
#   clean:  line_color=60  → 185-level contrast, survives denoising + erosion
#   messy:  line_color=90  → 155-level contrast, slight noise added
#   faded:  line_color=175 → 70-level contrast, intentionally hard to detect
_QUALITY_PARAMS = {
    "clean": dict(noise_sigma=3,  rotation_deg=0.0,  line_contrast=60),
    "messy": dict(noise_sigma=15, rotation_deg=1.5,  line_contrast=90),
    "faded": dict(noise_sigma=5,  rotation_deg=0.0,  line_contrast=175),
}

QualityLevel = Literal["clean", "messy", "faded"]


# ── Sample moves ──────────────────────────────────────────────────────────────

_SAMPLE_MOVES = [
    ("e4",   "e5"),
    ("Nf3",  "Nc6"),
    ("Bb5",  "a6"),
    ("Ba4",  "Nf6"),
    ("O-O",  "Be7"),
    ("Re1",  "b5"),
    ("Bb3",  "d6"),
    ("c3",   "O-O"),
    ("h3",   "Nb8"),
    ("d4",   "Nbd7"),
    ("Nbd2", "Bb7"),
    ("Bc2",  "Re8"),
    ("Nf1",  "Bf8"),
    ("Ng3",  "g6"),
    ("a4",   "c5"),
]


# ── Generator ─────────────────────────────────────────────────────────────────

@dataclass
class SyntheticScoresheet:
    """
    Generates a synthetic chess scoresheet image.

    Args:
        num_rows:    Number of move rows to draw (excluding header).
        quality:     One of "clean", "messy", "faded".
        double_table: If True, draw two side-by-side tables.
        width:       Image width in pixels.
        height:      Image height in pixels.
        seed:        Random seed for reproducibility.
    """
    num_rows: int = 15
    quality: QualityLevel = "clean"
    double_table: bool = False
    width: int = DEFAULT_WIDTH
    height: int = DEFAULT_HEIGHT
    seed: Optional[int] = 42

    def generate_bytes(self, fmt: str = "PNG") -> bytes:
        """Generate the image and return it as bytes."""
        img = self._build_image()
        buf = io.BytesIO()
        img.save(buf, format=fmt)
        return buf.getvalue()

    def generate_image(self) -> Image.Image:
        """Generate and return a PIL Image."""
        return self._build_image()

    # ── Internal ──────────────────────────────────────────────────────────────

    def _build_image(self) -> Image.Image:
        if self.seed is not None:
            random.seed(self.seed)
            np.random.seed(self.seed)  # _add_noise uses the numpy global RNG

        params = _QUALITY_PARAMS[self.quality]
        noise_sigma: int = params["noise_sigma"]
        rotation_deg: float = params["rotation_deg"]
        line_color: int = params["line_contrast"]  # 0=black, 255=white; lower=darker

        img = Image.new("L", (self.width, self.height), color=245)
        draw = ImageDraw.Draw(img)

        tables = 2 if self.double_table else 1
        table_width = (self.width - MARGIN_LEFT - MARGIN_RIGHT) // tables
        grid_height = self.height - MARGIN_TOP - MARGIN_BOTTOM

        for table_idx in range(tables):
            table_x = MARGIN_LEFT + table_idx * table_width
            self._draw_table(
                draw,
                x_start=table_x,
                y_start=MARGIN_TOP,
                width=table_width,
                height=grid_height,
                line_color=line_color,
                row_offset=table_idx * self.num_rows,
            )

        # Apply noise
        if noise_sigma > 0:
            img = self._add_noise(img, sigma=noise_sigma)

        # Apply rotation (simulates slight camera tilt)
        if abs(rotation_deg) > 0.01:
            img = img.rotate(rotation_deg, fillcolor=245, expand=False)

        return img

    def _draw_table(
        self,
        draw: ImageDraw.ImageDraw,
        x_start: int,
        y_start: int,
        width: int,
        height: int,
        line_color: int,
        row_offset: int,
    ) -> None:
        """Draw one scoresheet table (header + num_rows data rows)."""
        total_rows = self.num_rows + 1  # +1 for header
        row_height = height // total_rows

        # Column x positions
        col_widths = [int(width * r) for r in COLUMN_RATIOS]
        # Adjust last column to fill exactly
        col_widths[-1] = width - col_widths[0] - col_widths[1]

        x0 = x_start
        x1 = x0 + col_widths[0]
        x2 = x1 + col_widths[1]
        x3 = x2 + col_widths[2]
        y_bottom = y_start + height

        lc = line_color  # shorthand

        # Outer border
        draw.rectangle([x0, y_start, x3, y_bottom], outline=lc, width=2)

        # Vertical separators — width=2 so they survive morphological erosion
        draw.line([(x1, y_start), (x1, y_bottom)], fill=lc, width=2)
        draw.line([(x2, y_start), (x2, y_bottom)], fill=lc, width=2)

        # Horizontal lines — width=2 so they survive denoising + erosion
        for row in range(total_rows + 1):
            y = y_start + row * row_height
            draw.line([(x0, y), (x3, y)], fill=lc, width=2)

        # Header text
        header_y = y_start + row_height // 4
        self._draw_text(draw, x0 + 4, header_y, "No.", lc)
        self._draw_text(draw, x1 + 4, header_y, "White", lc)
        self._draw_text(draw, x2 + 4, header_y, "Black", lc)

        # Data rows
        for row in range(self.num_rows):
            y = y_start + (row + 1) * row_height + row_height // 4
            move_num = row + 1 + row_offset
            self._draw_text(draw, x0 + 4, y, str(move_num), lc)

            white_san, black_san = _SAMPLE_MOVES[row % len(_SAMPLE_MOVES)]
            self._draw_text(draw, x1 + 6, y, white_san, lc)
            self._draw_text(draw, x2 + 6, y, black_san, lc)

    @staticmethod
    def _draw_text(
        draw: ImageDraw.ImageDraw,
        x: int,
        y: int,
        text: str,
        color: int,
    ) -> None:
        """Draw text at (x, y) with fallback to default font."""
        try:
            font = ImageFont.load_default()
        except Exception:
            font = None
        draw.text((x, y), text, fill=color, font=font)

    @staticmethod
    def _add_noise(img: Image.Image, sigma: int) -> Image.Image:
        """Add Gaussian-like noise using PIL."""
        import numpy as np

        arr = np.array(img, dtype=np.int16)
        noise = np.random.randint(-sigma, sigma + 1, arr.shape, dtype=np.int16)
        arr = np.clip(arr + noise, 0, 255).astype(np.uint8)
        return Image.fromarray(arr, mode="L")


# ── Convenience functions ─────────────────────────────────────────────────────

def make_clean_scoresheet(num_rows: int = 10) -> bytes:
    """Return a clean synthetic scoresheet as PNG bytes."""
    return SyntheticScoresheet(num_rows=num_rows, quality="clean").generate_bytes()


def make_messy_scoresheet(num_rows: int = 10) -> bytes:
    """Return a messy (noisy, slightly rotated) scoresheet as PNG bytes."""
    return SyntheticScoresheet(num_rows=num_rows, quality="messy").generate_bytes()


def make_faded_scoresheet(num_rows: int = 10) -> bytes:
    """Return a low-contrast scoresheet as PNG bytes (for negative tests)."""
    return SyntheticScoresheet(num_rows=num_rows, quality="faded").generate_bytes()


def make_double_table_scoresheet(num_rows: int = 10) -> bytes:
    """Return a double-table scoresheet as PNG bytes."""
    return SyntheticScoresheet(
        num_rows=num_rows, quality="clean", double_table=True
    ).generate_bytes()
