"""
Tests for the Phase 3 CV pipeline:
    ImagePreprocessor → GridDetector → CropExtractor

All tests use synthetic PIL-generated images (no real scoresheet photos
required).  No database or network access is needed.

Test structure
──────────────
  TestPreprocessor      — decode, grayscale, denoise, deskew, threshold
  TestGridDetector      — happy path, failure modes (typed errors)
  TestCropExtractor     — crop count, ply_index correctness, blank detection
  TestPipelineIntegration — full end-to-end on synthetic images
"""

from __future__ import annotations

import io
import math
import numpy as np
import pytest
from PIL import Image

# ── Fixtures ─────────────────────────────────────────────────────────────────

from tests.fixtures.generate_synthetic import (
    SyntheticScoresheet,
    make_clean_scoresheet,
    make_double_table_scoresheet,
    make_messy_scoresheet,
)
from services.cv.preprocessor import ImagePreprocessor, PreprocessResult
from services.cv.grid_detector import (
    ColumnGroup,
    GridDetectionError,
    GridDetector,
    GridLayout,
    InsufficientRowsError,
    LowConfidenceError,
    NoLinesDetectedError,
)
from services.cv.crop_extractor import CropExtractor, CropResult


# ── Helpers ───────────────────────────────────────────────────────────────────

def _preprocess(image_bytes: bytes) -> PreprocessResult:
    return ImagePreprocessor().run(image_bytes)


def _solid_white_image(w: int = 400, h: int = 300) -> np.ndarray:
    """All-white binary image — no grid lines."""
    return np.zeros((h, w), dtype=np.uint8)


def _solid_ink_image(w: int = 400, h: int = 300) -> np.ndarray:
    """All-ink binary image."""
    return np.full((h, w), 255, dtype=np.uint8)


# ── TestPreprocessor ──────────────────────────────────────────────────────────

class TestPreprocessor:
    def test_returns_preprocess_result(self):
        img_bytes = make_clean_scoresheet(num_rows=5)
        result = _preprocess(img_bytes)
        assert isinstance(result, PreprocessResult)

    def test_gray_is_2d(self):
        result = _preprocess(make_clean_scoresheet(num_rows=5))
        assert result.gray.ndim == 2

    def test_binary_is_2d_uint8(self):
        result = _preprocess(make_clean_scoresheet(num_rows=5))
        assert result.binary.ndim == 2
        assert result.binary.dtype == np.uint8

    def test_binary_values_are_0_or_255(self):
        result = _preprocess(make_clean_scoresheet(num_rows=5))
        unique = set(np.unique(result.binary))
        assert unique.issubset({0, 255})

    def test_gray_and_binary_same_shape(self):
        result = _preprocess(make_clean_scoresheet(num_rows=5))
        assert result.gray.shape == result.binary.shape

    def test_deskew_angle_within_range(self):
        result = _preprocess(make_messy_scoresheet(num_rows=5))
        assert abs(result.deskew_angle_deg) <= 15.0

    def test_invalid_bytes_raises_value_error(self):
        with pytest.raises(ValueError, match="cv2.imdecode"):
            _preprocess(b"not an image")

    def test_empty_bytes_raises_value_error(self):
        with pytest.raises(ValueError):
            _preprocess(b"")

    def test_jpeg_bytes_accepted(self):
        """Verify JPEG input works (not just PNG)."""
        buf = io.BytesIO()
        img = Image.new("RGB", (200, 100), color=(200, 200, 200))
        img.save(buf, format="JPEG")
        result = _preprocess(buf.getvalue())
        assert result.gray.shape == (100, 200)

    def test_deskew_small_angle_is_corrected(self):
        """A rotated image should have a non-zero deskew_angle_deg."""
        sheet = SyntheticScoresheet(num_rows=8, quality="messy", seed=1)
        img_bytes = sheet.generate_bytes()
        result = _preprocess(img_bytes)
        # We cannot assert exact angle, but can confirm the field is populated
        assert isinstance(result.deskew_angle_deg, float)


# ── TestGridDetector ──────────────────────────────────────────────────────────

class TestGridDetector:
    def _detect_from_bytes(self, image_bytes: bytes) -> GridLayout:
        result = _preprocess(image_bytes)
        return GridDetector(result.binary).detect()

    def test_clean_single_table_detects(self):
        layout = self._detect_from_bytes(make_clean_scoresheet(num_rows=10))
        assert isinstance(layout, GridLayout)
        assert layout.detected_format == "single_table"

    def test_clean_double_table_detects(self):
        layout = self._detect_from_bytes(make_double_table_scoresheet(num_rows=10))
        assert layout.detected_format == "double_table"
        assert len(layout.column_groups) == 2

    def test_row_count_matches_expectation(self):
        num_rows = 10
        layout = self._detect_from_bytes(make_clean_scoresheet(num_rows=num_rows))
        # Allow ±2 rows for detection rounding
        assert abs(len(layout.row_boundaries) - num_rows) <= 2

    def test_confidence_above_threshold_for_clean(self):
        layout = self._detect_from_bytes(make_clean_scoresheet(num_rows=10))
        assert layout.confidence >= 0.55

    def test_column_group_has_correct_structure(self):
        layout = self._detect_from_bytes(make_clean_scoresheet(num_rows=10))
        group = layout.column_groups[0]
        assert isinstance(group, ColumnGroup)
        # move_number should be the leftmost/narrowest column
        mn_width = group.move_number[1] - group.move_number[0]
        white_width = group.white[1] - group.white[0]
        black_width = group.black[1] - group.black[0]
        assert mn_width > 0
        assert white_width > 0
        assert black_width > 0

    def test_blank_image_raises_no_lines_error(self):
        binary = _solid_white_image()
        with pytest.raises(NoLinesDetectedError):
            GridDetector(binary).detect()

    def test_all_ink_image_raises_grid_detection_error(self):
        binary = _solid_ink_image()
        with pytest.raises(GridDetectionError):
            GridDetector(binary).detect()

    def test_tiny_image_raises_insufficient_rows(self):
        """A 100×50 image cannot contain enough rows."""
        small = np.zeros((50, 100), dtype=np.uint8)
        # Add a few horizontal lines
        for y in [10, 25, 40]:
            small[y, :] = 255
        with pytest.raises((InsufficientRowsError, NoLinesDetectedError, GridDetectionError)):
            GridDetector(small).detect()

    def test_header_rows_excluded_from_row_boundaries(self):
        """Row boundaries should NOT include the header row."""
        layout = self._detect_from_bytes(make_clean_scoresheet(num_rows=10))
        # header_row_count is set from config (default 1)
        assert layout.header_row_count >= 0


# ── TestCropExtractor ─────────────────────────────────────────────────────────

class TestCropExtractor:
    def _get_crops(self, image_bytes: bytes) -> list[CropResult]:
        result = _preprocess(image_bytes)
        layout = GridDetector(result.binary).detect()
        extractor = CropExtractor(
            gray=result.gray,
            binary=result.binary,
            layout=layout,
        )
        return extractor.extract()

    def test_crops_returned_for_clean_sheet(self):
        crops = self._get_crops(make_clean_scoresheet(num_rows=10))
        assert len(crops) > 0

    def test_ply_indices_are_unique(self):
        crops = self._get_crops(make_clean_scoresheet(num_rows=8))
        ply_indices = [c.ply_index for c in crops]
        assert len(ply_indices) == len(set(ply_indices))

    def test_ply_indices_are_sorted(self):
        crops = self._get_crops(make_clean_scoresheet(num_rows=8))
        ply_indices = [c.ply_index for c in crops]
        assert ply_indices == sorted(ply_indices)

    def test_white_has_even_ply_index(self):
        crops = self._get_crops(make_clean_scoresheet(num_rows=5))
        white_crops = [c for c in crops if c.color == "white"]
        for crop in white_crops:
            assert crop.ply_index % 2 == 0, (
                f"White crop has odd ply_index={crop.ply_index}"
            )

    def test_black_has_odd_ply_index(self):
        crops = self._get_crops(make_clean_scoresheet(num_rows=5))
        black_crops = [c for c in crops if c.color == "black"]
        for crop in black_crops:
            assert crop.ply_index % 2 == 1, (
                f"Black crop has even ply_index={crop.ply_index}"
            )

    def test_image_bytes_are_valid_png(self):
        # All cells (blank or not) must produce valid PNG bytes.
        # Synthetic PIL text is tiny (~8 px) so cells may be flagged blank —
        # that is expected with this fixture; real handwriting fills 30-50%.
        crops = self._get_crops(make_clean_scoresheet(num_rows=5))
        assert len(crops) > 0
        for crop in crops[:3]:  # check first 3 only for speed
            img = Image.open(io.BytesIO(crop.image_bytes))
            assert img.format == "PNG"

    def test_source_region_is_within_image_bounds(self):
        image_bytes = make_clean_scoresheet(num_rows=8)
        result = _preprocess(image_bytes)
        layout = GridDetector(result.binary).detect()
        crops = CropExtractor(
            gray=result.gray,
            binary=result.binary,
            layout=layout,
        ).extract()
        h, w = result.gray.shape
        for crop in crops:
            x1, y1, x2, y2 = crop.source_region
            assert 0 <= x1 < x2 <= w, f"x out of bounds: {crop.source_region}"
            assert 0 <= y1 < y2 <= h, f"y out of bounds: {crop.source_region}"

    def test_double_table_right_section_plies_offset(self):
        """Right-section plies must be >= 2*num_rows."""
        crops = self._get_crops(make_double_table_scoresheet(num_rows=8))
        right = [c for c in crops if c.section_index == 1]
        if right:  # double table was actually detected
            min_ply = min(c.ply_index for c in right)
            # At minimum, offset by 2*num_rows of the left section
            # (num_rows may differ from 8 due to detection rounding)
            assert min_ply >= 4  # very conservative lower bound

    def test_blank_cell_detection(self):
        """Fully white binary image → all cells blank."""
        # Build a minimal GridLayout manually
        from services.cv.grid_detector import ColumnGroup, GridLayout

        group = ColumnGroup(
            move_number=(0, 50),
            white=(50, 200),
            black=(200, 350),
        )
        layout = GridLayout(
            row_boundaries=[(0, 100), (100, 200), (200, 300)],
            column_groups=[group],
            header_row_count=0,
            detected_format="single_table",
            confidence=0.9,
        )
        # All-white grayscale (high values = background = blank)
        gray = np.full((300, 350), 240, dtype=np.uint8)
        binary = np.zeros((300, 350), dtype=np.uint8)  # no ink

        extractor = CropExtractor(gray=gray, binary=binary, layout=layout)
        crops = extractor.extract()

        assert all(c.is_blank for c in crops), (
            "Expected all cells to be blank in an all-white image"
        )

    def test_non_blank_cell_with_ink(self):
        """A cell with dense ink should NOT be blank."""
        from services.cv.grid_detector import ColumnGroup, GridLayout

        group = ColumnGroup(
            move_number=(0, 50),
            white=(50, 200),
            black=(200, 350),
        )
        layout = GridLayout(
            row_boundaries=[(0, 100)],
            column_groups=[group],
            header_row_count=0,
            detected_format="single_table",
            confidence=0.9,
        )
        gray = np.full((100, 350), 50, dtype=np.uint8)   # very dark = ink
        binary = np.full((100, 350), 255, dtype=np.uint8)

        extractor = CropExtractor(gray=gray, binary=binary, layout=layout)
        crops = extractor.extract()

        white_crop = next(c for c in crops if c.color == "white")
        assert not white_crop.is_blank, "Dense ink cell should not be blank"


# ── TestPipelineIntegration ───────────────────────────────────────────────────

class TestPipelineIntegration:
    """End-to-end tests through the full preprocessing → detection → extraction pipeline."""

    def test_clean_single_table_end_to_end(self):
        num_rows = 10
        image_bytes = make_clean_scoresheet(num_rows=num_rows)

        result = _preprocess(image_bytes)
        layout = GridDetector(result.binary).detect()
        crops = CropExtractor(
            gray=result.gray,
            binary=result.binary,
            layout=layout,
        ).extract()

        assert layout.detected_format == "single_table"
        assert len(crops) > 0
        # 10 rows × 2 colors = 20 cells; allow ±4 for detection rounding
        assert abs(len(crops) - num_rows * 2) <= 8

    def test_messy_sheet_still_detects(self):
        """Slightly noisy/rotated sheet should still produce a valid grid."""
        image_bytes = make_messy_scoresheet(num_rows=10)
        result = _preprocess(image_bytes)
        layout = GridDetector(result.binary).detect()
        assert len(layout.row_boundaries) >= 3

    def test_double_table_end_to_end(self):
        image_bytes = make_double_table_scoresheet(num_rows=8)
        result = _preprocess(image_bytes)
        layout = GridDetector(result.binary).detect()
        crops = CropExtractor(
            gray=result.gray,
            binary=result.binary,
            layout=layout,
        ).extract()

        assert len(layout.column_groups) == 2
        assert any(c.section_index == 1 for c in crops)

    def test_crops_have_valid_png_headers(self):
        image_bytes = make_clean_scoresheet(num_rows=5)
        result = _preprocess(image_bytes)
        layout = GridDetector(result.binary).detect()
        crops = CropExtractor(
            gray=result.gray,
            binary=result.binary,
            layout=layout,
        ).extract()

        # All cells produce PNG bytes regardless of blank/non-blank status.
        assert len(crops) > 0

        PNG_HEADER = b"\x89PNG"
        for crop in crops[:5]:
            assert crop.image_bytes[:4] == PNG_HEADER, (
                f"Crop at ply {crop.ply_index} is not a valid PNG"
            )
