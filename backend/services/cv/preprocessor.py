"""
Image preprocessing pipeline for chess scoresheet photos.

Pipeline (in order):
    1. Decode — accept raw bytes (JPEG/PNG/WebP/TIFF) → BGR array
    2. Grayscale — convert BGR → single-channel gray
    3. Denoise — fastNlMeansDenoising (h=10, template/search windows standard)
    4. Deskew — detect dominant line angle via HoughLinesP on Otsu binary,
                median angle correction via warpAffine (up to ±15°)
    5. Adaptive threshold — Gaussian method → clean binary for grid detection

All steps are pure functions collected in ImagePreprocessor.run().
Returns a PreprocessResult with both arrays for downstream use.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import cv2
import numpy as np

logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────

# Maximum skew angle we attempt to correct.  Beyond this the image is
# rotated/cropped so badly that deskewing would make things worse.
_MAX_DESKEW_ANGLE_DEG: float = 15.0

# fastNlMeansDenoising strength.  10 is a safe default for typical phone photos.
_DENOISE_H: int = 10

# Adaptive threshold block size and C offset.
_ADAPTIVE_BLOCK_SIZE: int = 31   # must be odd
_ADAPTIVE_C: int = 10            # subtracted from weighted mean


# ── Result type ───────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class PreprocessResult:
    """Output of the full preprocessing pipeline."""

    # Single-channel grayscale (uint8) — not yet thresholded.
    gray: np.ndarray

    # Binary image (uint8, 0 or 255) produced by adaptive Gaussian threshold.
    # White = background, black = ink (THRESH_BINARY_INV is applied).
    binary: np.ndarray

    # Actual deskew angle applied in degrees (positive = counter-clockwise).
    # 0.0 means no correction was needed or possible.
    deskew_angle_deg: float


# ── Preprocessor ──────────────────────────────────────────────────────────────

class ImagePreprocessor:
    """
    Stateless pipeline that converts a raw image bytestring into a
    PreprocessResult ready for grid detection.

    Usage:
        result = ImagePreprocessor().run(image_bytes)
    """

    # ── Public API ────────────────────────────────────────────────────────────

    def run(self, image_bytes: bytes) -> PreprocessResult:
        """
        Execute the full pipeline.

        Args:
            image_bytes: Raw bytes of a JPEG, PNG, WebP, or TIFF image.

        Returns:
            PreprocessResult with .gray, .binary, .deskew_angle_deg.

        Raises:
            ValueError: If the bytes cannot be decoded as an image.
        """
        bgr = self._decode(image_bytes)
        gray = self._to_grayscale(bgr)
        denoised = self._denoise(gray)
        deskewed, angle = self._deskew(denoised)
        binary = self._adaptive_threshold(deskewed)

        logger.debug(
            "Preprocessing complete — size=%dx%d deskew=%.2f°",
            deskewed.shape[1],
            deskewed.shape[0],
            angle,
        )

        return PreprocessResult(gray=deskewed, binary=binary, deskew_angle_deg=angle)

    # ── Pipeline steps ────────────────────────────────────────────────────────

    @staticmethod
    def _decode(image_bytes: bytes) -> np.ndarray:
        """Decode raw bytes into a BGR OpenCV array."""
        if not image_bytes:
            raise ValueError("image_bytes is empty.")
        buf = np.frombuffer(image_bytes, dtype=np.uint8)
        try:
            bgr = cv2.imdecode(buf, cv2.IMREAD_COLOR)
        except Exception as exc:
            raise ValueError(
                f"cv2.imdecode raised an error — image bytes may be corrupt: {exc}"
            ) from exc
        if bgr is None:
            raise ValueError(
                "cv2.imdecode returned None — image bytes are corrupt or "
                "the format is not supported (expected JPEG/PNG/WebP/TIFF)."
            )
        return bgr

    @staticmethod
    def _to_grayscale(bgr: np.ndarray) -> np.ndarray:
        """Convert BGR to single-channel grayscale."""
        return cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)

    @staticmethod
    def _denoise(gray: np.ndarray) -> np.ndarray:
        """
        Apply fast non-local means denoising.

        h=10 is conservative — strong enough to reduce JPEG compression
        artefacts and mild noise from phone cameras without blurring thin
        grid lines.
        """
        return cv2.fastNlMeansDenoising(gray, h=_DENOISE_H)

    @staticmethod
    def _deskew(gray: np.ndarray) -> tuple[np.ndarray, float]:
        """
        Estimate and correct document skew using Hough line detection.

        Algorithm:
            1. Compute Otsu binary of the grayscale.
            2. Detect lines with HoughLinesP.
            3. Compute the angle of each near-horizontal or near-vertical line.
            4. Take the *median* angle to suppress outliers.
            5. If |angle| <= _MAX_DESKEW_ANGLE_DEG, apply warpAffine.

        Returns:
            (corrected_gray, angle_applied_deg)
        """
        # Otsu threshold for line detection only (not returned as final binary)
        _, otsu = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

        h, w = gray.shape
        min_line_length = max(50, w // 6)  # at least 1/6 of image width
        lines = cv2.HoughLinesP(
            otsu,
            rho=1,
            theta=np.pi / 180,
            threshold=80,
            minLineLength=min_line_length,
            maxLineGap=20,
        )

        if lines is None:
            logger.debug("Deskew: no lines found, skipping correction.")
            return gray, 0.0

        angles: list[float] = []
        for line in lines:
            x1, y1, x2, y2 = line[0]
            dx = x2 - x1
            dy = y2 - y1
            if dx == 0:
                continue
            angle_deg = np.degrees(np.arctan2(dy, dx))
            # Only keep near-horizontal lines (±45°) to measure page tilt.
            if abs(angle_deg) <= 45.0:
                angles.append(angle_deg)

        if not angles:
            logger.debug("Deskew: no usable horizontal lines, skipping correction.")
            return gray, 0.0

        median_angle = float(np.median(angles))

        if abs(median_angle) > _MAX_DESKEW_ANGLE_DEG:
            logger.warning(
                "Deskew: detected angle %.2f° exceeds limit (%.1f°), skipping.",
                median_angle,
                _MAX_DESKEW_ANGLE_DEG,
            )
            return gray, 0.0

        if abs(median_angle) < 0.1:
            # Negligible — avoid unnecessary interpolation artefacts.
            return gray, 0.0

        center = (w / 2.0, h / 2.0)
        M = cv2.getRotationMatrix2D(center, median_angle, 1.0)
        corrected = cv2.warpAffine(
            gray,
            M,
            (w, h),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_REPLICATE,
        )
        logger.debug("Deskew: corrected by %.2f°", median_angle)
        return corrected, median_angle

    @staticmethod
    def _adaptive_threshold(gray: np.ndarray) -> np.ndarray:
        """
        Convert grayscale to binary using Gaussian adaptive thresholding.

        THRESH_BINARY_INV: ink (dark) → 255 (foreground), background → 0.
        This convention makes projection sums / morphological ops intuitive:
        high sum = many ink pixels = likely a grid line region.
        """
        return cv2.adaptiveThreshold(
            gray,
            maxValue=255,
            adaptiveMethod=cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
            thresholdType=cv2.THRESH_BINARY_INV,
            blockSize=_ADAPTIVE_BLOCK_SIZE,
            C=_ADAPTIVE_C,
        )
