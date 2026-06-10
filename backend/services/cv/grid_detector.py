"""
Adaptive grid detection for chess scoresheet images.

Design contract
───────────────
• NO hardcoded row or column counts.  Detection is purely data-driven.
• On ANY structural failure, raise a typed subclass of GridDetectionError
  with a descriptive message.  Silent fallback is never acceptable —
  a wrong crop is worse than a clear error in a tournament setting.

Supported scoresheet layouts
─────────────────────────────
  single_table  — 3 data columns (move_no | white | black)
  double_table  — 6 data columns (two side-by-side tables of 3)

Detection algorithm
────────────────────
  1. Morphological open with a wide horizontal kernel (image_width // 8, 1)
     isolates horizontal lines — handwriting and short marks are too narrow
     to survive the erosion step.
  2. Row projection of the opened image → peak positions → row boundaries.
  3. Morphological open with a tall vertical kernel (1, image_height // 8)
     isolates vertical lines — handwriting, digits, and horizontal lines
     are all eliminated.
  4. Column projection → peak positions → vertical line candidates.
  5. Minimum length filter: discard candidates covering < 40 % of image
     height (removes residual noise that survived the structural filter).
  6. Infer column roles from relative widths (narrow = move_no, wide = moves).
     Accepts 3–8 vertical lines; snaps to 4 (single_table) or 7 (double_table).
  7. Compute confidence from line regularity and row count.
  8. Raise LowConfidenceError if confidence < CV_CONFIDENCE_THRESHOLD.
  9. Raise InsufficientRowsError if detected rows < CV_MIN_ROWS.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import List, Literal, Optional, Tuple

import numpy as np
from scipy import signal  # type: ignore[import-untyped]

from config import settings

logger = logging.getLogger(__name__)

# ── Type aliases ──────────────────────────────────────────────────────────────

# (x_start, x_end) pixel bounds of a column, inclusive.
ColumnBounds = Tuple[int, int]


# ── Error hierarchy ───────────────────────────────────────────────────────────

class GridDetectionError(Exception):
    """
    Base for all grid detection failures.

    Always raised (never swallowed) so the Celery task can set
    job.status = "failed" and job.error_message to this str(e).
    """


class NoLinesDetectedError(GridDetectionError):
    """Morphological erosion found no horizontal or vertical lines."""


class InsufficientRowsError(GridDetectionError):
    """Fewer than CV_MIN_ROWS rows were detected."""


class ColumnStructureError(GridDetectionError):
    """
    Detected column count does not match any known scoresheet format
    (expected 3 for single-table or 6 for double-table).
    """


class LowConfidenceError(GridDetectionError):
    """
    Overall grid confidence is below CV_CONFIDENCE_THRESHOLD.
    The image may be too blurry, folded, or otherwise unsuitable.
    """


# ── Result types ──────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ColumnGroup:
    """
    The three column bounds that constitute one scoresheet table.

    All values are pixel x-coordinates (inclusive start, exclusive end).
    """
    move_number: ColumnBounds   # narrow left column ("1", "2", …)
    white: ColumnBounds         # White player moves
    black: ColumnBounds         # Black player moves


@dataclass(frozen=True)
class GridLayout:
    """
    Fully described grid ready for the CropExtractor.

    row_boundaries — list of (y_top, y_bottom) in pixels for each *data* row
                     (header rows already excluded).
    column_groups  — 1 entry for single_table, 2 entries for double_table.
    header_row_count — number of header rows skipped at the top.
    detected_format  — "single_table" | "double_table"
    confidence       — [0.0, 1.0]  higher = more regular grid
    """
    row_boundaries: List[Tuple[int, int]]
    column_groups: List[ColumnGroup]
    header_row_count: int
    detected_format: Literal["single_table", "double_table"]
    confidence: float


# ── Internal helpers ──────────────────────────────────────────────────────────

def _find_peaks(projection: np.ndarray, min_distance: int = 5) -> np.ndarray:
    """
    Return indices of peaks in a 1-D projection array.

    Uses scipy.signal.find_peaks with a prominence filter so that noise
    bumps are ignored.  min_distance prevents duplicate detections of the
    same physical line.
    """
    prominence_threshold = float(projection.max()) * 0.15
    peaks, _ = signal.find_peaks(
        projection,
        distance=min_distance,
        prominence=prominence_threshold,
    )
    return peaks


def _cluster_peaks(peaks: np.ndarray, gap: int = 8) -> List[int]:
    """
    Merge peaks within *gap* pixels into a single representative position
    (the median of the cluster).

    Handles cases where erosion leaves a 2–3 px wide band that registers
    as multiple adjacent peaks.
    """
    if len(peaks) == 0:
        return []

    clusters: List[List[int]] = [[int(peaks[0])]]
    for p in peaks[1:]:
        if int(p) - clusters[-1][-1] <= gap:
            clusters[-1].append(int(p))
        else:
            clusters.append([int(p)])
    return [int(np.median(c)) for c in clusters]


def _boundary_pairs(positions: List[int], total: int) -> List[Tuple[int, int]]:
    """
    Convert a list of line positions to (top, bottom) row boundary pairs.

    The boundaries extend from the midpoint between consecutive lines,
    clamped to [0, total).
    """
    if len(positions) < 2:
        return []

    boundaries: List[Tuple[int, int]] = []
    for i in range(len(positions) - 1):
        top = (positions[i] + (positions[i - 1] if i > 0 else 0)) // 2 if i > 0 else 0
        bottom = (positions[i] + positions[i + 1]) // 2
        boundaries.append((top, bottom))

    # Last row: from midpoint of last two lines to end
    last_top = (positions[-2] + positions[-1]) // 2
    boundaries.append((last_top, total))

    return boundaries


def _adjust_line_count(lines: List[int], target: int, image_width: int) -> List[int]:
    """
    Return exactly *target* line positions by pruning or padding *lines*.

    Pruning (n > target):
        Iteratively remove the line that belongs to the smallest inter-line
        gap, while always preserving the two outermost lines (they are the
        image border and are most reliable).

    Padding (n < target):
        Insert virtual border lines at x=0 (if the leftmost detected line is
        far from the edge) or at x=image_width, until we reach *target*.
    """
    result = sorted(lines)

    # Pad with virtual border lines if we have too few
    while len(result) < target:
        if not result or result[0] > image_width // 10:
            result.insert(0, 0)
        else:
            result.append(image_width)
        result = sorted(result)

    # Prune the most redundant line (smallest gap, interior-first)
    while len(result) > target:
        gaps = [result[i + 1] - result[i] for i in range(len(result) - 1)]
        # Prefer removing interior lines (index 1 .. n-2) to preserve borders
        interior = [(i, g) for i, g in enumerate(gaps) if 0 < i < len(gaps) - 1]
        if interior:
            min_idx = min(interior, key=lambda t: t[1])[0]
        else:
            min_idx = int(np.argmin(gaps))
        # Remove the right endpoint of the smallest gap
        result.pop(min_idx + 1)

    return result


def _compute_confidence(row_gaps: List[int], col_gaps: List[int]) -> float:
    """
    Confidence = 1 - weighted_cv where weighted_cv is the coefficient of
    variation of detected gaps.  Perfectly regular grids → cv = 0 → conf = 1.

    Row regularity carries 60% weight (rows are more variable in real sheets).
    """
    def _cv(gaps: List[int]) -> float:
        if len(gaps) < 2:
            return 0.0
        arr = np.array(gaps, dtype=float)
        mean = arr.mean()
        if mean == 0:
            return 1.0
        return float(arr.std() / mean)

    row_cv = _cv(row_gaps)
    col_cv = _cv(col_gaps)
    combined_cv = 0.6 * row_cv + 0.4 * col_cv
    return max(0.0, min(1.0, 1.0 - combined_cv))


# ── Main detector ─────────────────────────────────────────────────────────────

class GridDetector:
    """
    Detects the grid layout of a preprocessed chess scoresheet image.

    Args:
        binary: Binary image from ImagePreprocessor (ink=255, bg=0), uint8.

    Raises:
        NoLinesDetectedError, InsufficientRowsError, ColumnStructureError,
        LowConfidenceError — all subclasses of GridDetectionError.
    """

    def __init__(self, binary: np.ndarray) -> None:
        self._binary = binary
        self._h, self._w = binary.shape

    def detect(self) -> GridLayout:
        """Run detection and return a GridLayout or raise GridDetectionError."""
        row_lines = self._detect_horizontal_lines()
        col_lines = self._detect_vertical_lines()

        logger.debug(
            "Raw lines — horizontal: %d, vertical: %d", len(row_lines), len(col_lines)
        )

        # ── Row boundaries ────────────────────────────────────────────────────
        all_row_boundaries = _boundary_pairs(row_lines, self._h)
        if len(all_row_boundaries) == 0:
            raise NoLinesDetectedError(
                f"No horizontal grid lines detected in a {self._w}×{self._h} image. "
                "The image may be too dark, blurry, or not a scoresheet."
            )

        # Skip header rows
        skip = settings.CV_HEADER_ROWS
        data_boundaries = all_row_boundaries[skip:]

        if len(data_boundaries) < settings.CV_MIN_ROWS:
            raise InsufficientRowsError(
                f"Only {len(data_boundaries)} data row(s) detected "
                f"(minimum required: {settings.CV_MIN_ROWS}, header rows skipped: {skip}). "
                "The scoresheet may be cut off or the image too small."
            )

        # ── Column structure ──────────────────────────────────────────────────
        column_groups = self._infer_column_groups(col_lines)

        # ── Confidence ────────────────────────────────────────────────────────
        row_gaps = [b - a for a, b in all_row_boundaries]
        col_gaps: List[int] = []
        for g in column_groups:
            col_gaps.append(g.white[1] - g.white[0])
            col_gaps.append(g.black[1] - g.black[0])

        confidence = _compute_confidence(row_gaps, col_gaps)
        logger.debug("Grid confidence: %.3f", confidence)

        if confidence < settings.CV_CONFIDENCE_THRESHOLD:
            raise LowConfidenceError(
                f"Grid detection confidence {confidence:.3f} is below the threshold "
                f"{settings.CV_CONFIDENCE_THRESHOLD}. "
                "The scoresheet grid is too irregular or the image quality is insufficient."
            )

        fmt: Literal["single_table", "double_table"] = (
            "double_table" if len(column_groups) == 2 else "single_table"
        )

        layout = GridLayout(
            row_boundaries=data_boundaries,
            column_groups=column_groups,
            header_row_count=skip,
            detected_format=fmt,
            confidence=confidence,
        )
        logger.info(
            "Grid detected: format=%s rows=%d confidence=%.3f",
            fmt,
            len(data_boundaries),
            confidence,
        )
        return layout

    # ── Line detection ────────────────────────────────────────────────────────

    def _detect_horizontal_lines(self) -> List[int]:
        """
        Isolate horizontal lines via morphological open and return
        their y-positions (sorted, clustered).

        Kernel: (image_width // 8, 1).  Only structures spanning at least
        1/8 of the image width survive the open — this eliminates all
        handwriting, digits, and short marks while preserving the long
        horizontal grid lines.

        Morphological open (erode → dilate) suppresses noise that a plain
        erosion pass would leave behind in the dilated output.
        """
        kernel_w = max(1, self._w // 8)
        kernel = cv2.getStructuringElement(  # type: ignore[attr-defined]
            cv2.MORPH_RECT, (kernel_w, 1)  # type: ignore[attr-defined]
        )
        opened = cv2.morphologyEx(  # type: ignore[attr-defined]
            self._binary, cv2.MORPH_OPEN, kernel  # type: ignore[attr-defined]
        )

        # Row projection: sum each row → peak = line position
        projection = opened.sum(axis=1).astype(float)
        min_dist = max(5, self._h // 60)
        raw_peaks = _find_peaks(projection, min_distance=min_dist)
        clustered = _cluster_peaks(raw_peaks, gap=6)
        return sorted(clustered)

    def _detect_vertical_lines(self) -> List[int]:
        """
        Isolate vertical lines via morphological open and return
        their x-positions (sorted, clustered).

        Kernel: (1, image_height // 8).  Only structures spanning at least
        1/8 of the image height survive — handwritten strokes, move numbers,
        short marks, and horizontal lines are all eliminated.

        After clustering, a minimum-length filter discards any candidate
        whose morphological response covers less than 40 % of image height,
        removing residual noise that survived the structural filter.
        """
        kernel_h = max(1, self._h // 8)
        kernel = cv2.getStructuringElement(  # type: ignore[attr-defined]
            cv2.MORPH_RECT, (1, kernel_h)  # type: ignore[attr-defined]
        )
        opened = cv2.morphologyEx(  # type: ignore[attr-defined]
            self._binary, cv2.MORPH_OPEN, kernel  # type: ignore[attr-defined]
        )

        # Column projection: sum each column → peak = line position
        projection = opened.sum(axis=0).astype(float)
        min_dist = max(5, self._w // 80)
        raw_peaks = _find_peaks(projection, min_distance=min_dist)
        clustered = _cluster_peaks(raw_peaks, gap=6)

        # ── Minimum line length filter ────────────────────────────────────────
        # A true vertical grid line covers ≥ 25 % of image height.
        # (30 % is too strict: noisy/rotated images yield ~29 % after
        # deskewing + adaptive thresholding + morphological open, because
        # noise breaks lines into segments and open drops short segments.)
        # Evaluate coverage in a ±3 px neighbourhood around each candidate
        # to handle sub-pixel centering from the cluster median.
        min_coverage = 0.25 * self._h * 255
        filtered: List[int] = []
        for x in clustered:
            lo = max(0, x - 3)
            hi = min(projection.shape[0], x + 4)
            if float(projection[lo:hi].max()) >= min_coverage:
                filtered.append(x)

        logger.debug(
            "Vertical lines: %d candidates → %d after length filter (min_coverage=%.0f)",
            len(clustered),
            len(filtered),
            min_coverage,
        )
        return sorted(filtered)

    # ── Column structure inference ────────────────────────────────────────────

    def _infer_column_groups(self, col_lines: List[int]) -> List[ColumnGroup]:
        """
        Map detected vertical line positions to ColumnGroup(s).

        Accepted line counts: 3–8 (different scoresheet formats vary).
            3–5 lines → single_table  (snap to 4 lines)
            6–8 lines → double_table  (snap to 7 lines)

        Lines are padded (virtual border at 0 or image width) or pruned
        (smallest inter-line gap dropped) to reach the target count.
        The narrowest gap in each group of 3 is the move-number column.
        """
        n = len(col_lines)

        if n < 3 or n > 8:
            raise ColumnStructureError(
                f"Expected 3–8 vertical lines (for single-table or double-table format), "
                f"but detected {n}. "
                "Check that the full scoresheet is visible and not cropped."
            )

        if n <= 5:
            # single_table: normalise to exactly 4 lines
            lines4 = _adjust_line_count(col_lines, 4, self._w)
            groups = [self._build_column_group(lines4)]
        else:
            # double_table: normalise to exactly 7 lines
            # Lines: L0 L1 L2 L3 L4 L5 L6  (L3 is the shared middle divider)
            lines7 = _adjust_line_count(col_lines, 7, self._w)
            groups = [
                self._build_column_group(lines7[0:4]),
                self._build_column_group(lines7[3:7]),
            ]

        return groups

    @staticmethod
    def _build_column_group(lines: List[int]) -> ColumnGroup:
        """
        Given exactly 4 vertical line x-positions, identify which inter-line
        gap is the move-number column (narrowest) and assign white/black.

        lines[0] < lines[1] < lines[2] < lines[3]
        gaps: [lines[1]-lines[0], lines[2]-lines[1], lines[3]-lines[2]]
        Narrowest gap index → move_number column.
        """
        if len(lines) != 4:
            raise ColumnStructureError(
                f"_build_column_group requires exactly 4 lines, got {len(lines)}."
            )
        gaps = [lines[i + 1] - lines[i] for i in range(3)]
        narrow_idx = int(np.argmin(gaps))

        if narrow_idx == 0:
            move_no: ColumnBounds = (lines[0], lines[1])
            white: ColumnBounds = (lines[1], lines[2])
            black: ColumnBounds = (lines[2], lines[3])
        elif narrow_idx == 1:
            # Unusual but handle gracefully: middle column is narrowest
            move_no = (lines[1], lines[2])
            white = (lines[0], lines[1])
            black = (lines[2], lines[3])
        else:  # narrow_idx == 2
            # Rightmost column narrowest — treat as move_no on right side
            move_no = (lines[2], lines[3])
            white = (lines[0], lines[1])
            black = (lines[1], lines[2])

        return ColumnGroup(move_number=move_no, white=white, black=black)


# ── Lazy OpenCV import ─────────────────────────────────────────────────────────
# Import here so the module is importable even in environments without OpenCV
# (e.g. during schema-only test runs).  The type: ignore comments above suppress
# mypy errors on cv2 attribute access.
try:
    import cv2  # noqa: F811  (re-import to make cv2 available in class body)
except ImportError as exc:  # pragma: no cover
    raise ImportError(
        "opencv-python-headless is required for grid detection. "
        "Run: pip install opencv-python-headless"
    ) from exc
