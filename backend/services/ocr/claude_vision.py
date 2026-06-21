"""
Claude Vision OCR provider — primary backend.

Reads the ENTIRE scoresheet photograph in a single API call instead of
recognising isolated cell crops.  This is deliberately different from the
TrOCR per-crop design:

  • The model sees the printed move numbers and column structure, so it
    knows which cell belongs to which (move_number, color) pair.
  • Handwriting is read in context — "Nf3" after "e4 e5" is far easier to
    disambiguate than a 60×40 px crop in isolation.
  • Grid detection failures stop being fatal: the pipeline can still get a
    full move list even when OpenCV cannot find the table lines.

The provider also implements the standard OCRProvider.recognise_batch()
interface (crops are sent as numbered images in one request) so it remains
interchangeable with TrOCR/Tesseract where per-crop reading is needed.

Authentication: settings.ANTHROPIC_API_KEY, or the ANTHROPIC_API_KEY
environment variable (SDK default resolution).
"""

from __future__ import annotations

import base64
import io
import json
import logging
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from config import settings
from services.ocr.base import OCRCandidate, OCRPrediction, OCRProvider

logger = logging.getLogger(__name__)


class ClaudeVisionError(RuntimeError):
    """Raised when the Claude API call or response parsing fails.

    The processing pipeline catches this and (if OCR_FALLBACK_TO_TROCR is
    enabled) retries with the local TrOCR model.
    """


# ── Result types ──────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class SheetMove:
    """One move cell read from a full scoresheet image."""
    move_number: int          # 1-based move number as printed on the sheet
    color: str                # "white" | "black"
    text: str                 # transcribed SAN-like text, e.g. "Nf3", "O-O"
    confidence: float         # model's self-reported confidence [0, 1]
    alternates: Tuple[str, ...] = field(default_factory=tuple)

    @property
    def ply_index(self) -> int:
        """0-based ply: white moves are even, black moves are odd."""
        return (self.move_number - 1) * 2 + (0 if self.color == "white" else 1)


# ── Output schema (structured outputs) ────────────────────────────────────────
# Structured outputs do not support numeric min/max constraints, so the
# confidence range is enforced by clamping after parsing.

_SHEET_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "moves": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "move_number": {"type": "integer"},
                    "color": {"type": "string", "enum": ["white", "black"]},
                    "text": {"type": "string"},
                    "confidence": {"type": "number"},
                    "alternates": {
                        "type": "array",
                        "items": {"type": "string"},
                    },
                },
                "required": ["move_number", "color", "text", "confidence", "alternates"],
                "additionalProperties": False,
            },
        },
        "result_notation": {
            "type": ["string", "null"],
            "description": "Game result if written on the sheet (1-0, 0-1, 1/2-1/2), else null",
        },
    },
    "required": ["moves", "result_notation"],
    "additionalProperties": False,
}

_BATCH_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "readings": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "image_index": {"type": "integer"},
                    "text": {"type": "string"},
                    "confidence": {"type": "number"},
                    "alternates": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["image_index", "text", "confidence", "alternates"],
                "additionalProperties": False,
            },
        },
    },
    "required": ["readings"],
    "additionalProperties": False,
}

_SHEET_SYSTEM_PROMPT = """\
You are an expert chess arbiter's assistant that transcribes handwritten chess \
scoresheets with maximum fidelity.

Rules:
- Read EVERY cell that contains handwriting, in order. Use the printed move \
numbers on the sheet to assign move_number; the left column of a move pair is \
white, the right column is black.
- Transcribe what is actually written. Do NOT silently correct moves that look \
illegal — faithfulness over plausibility. Chess validation happens downstream.
- Normalise notation glyphs only: castling written as 00/0-0 → "O-O", \
000/0-0-0 → "O-O-O"; "х"/"×" → "x"; trailing check/mate symbols keep "+"/"#".
- The sheet may be in a non-English notation (e.g. Turkish: A=knight(N), \
F=bishop(B), K=rook(R), V=queen(Q), Ş=king(K); German: S,L,T,D,K; etc.). \
Transcribe the letters as written — do NOT translate to English piece letters. \
Put a translated English-SAN guess in alternates if you are confident.
- Empty cells, crossed-out cells and the header row are skipped entirely.
- confidence is YOUR certainty the transcription matches the ink, 0.0–1.0. \
Use values below 0.6 for genuinely hard-to-read cells.
- alternates: up to 3 plausible alternative readings for ambiguous handwriting \
(e.g. "Nc3" vs "Ne3"), best first. Empty array if unambiguous.
- If the sheet has two side-by-side tables, the right table continues the move \
numbering of the left table.
"""

_BATCH_SYSTEM_PROMPT = """\
You transcribe handwritten chess move cells. Each image is one cell cropped \
from a scoresheet and contains at most one chess move in algebraic notation \
(possibly in a non-English letter scheme — transcribe letters as written).
Return one reading per image, matched by image_index (0-based, in the order \
the images appear). Use text="" with confidence=0 for blank or unreadable \
cells. alternates: up to 3 plausible alternative readings, best first.
"""


# ── Client (lazy singleton) ───────────────────────────────────────────────────

_client: Optional[Any] = None


def _get_client() -> Any:
    """Create or return the cached Anthropic client."""
    global _client
    if _client is not None:
        return _client

    api_key = (
        settings.ANTHROPIC_API_KEY or os.environ.get("ANTHROPIC_API_KEY", "")
    ).strip()
    if not api_key:
        raise ClaudeVisionError(
            "OCR_BACKEND=claude requires ANTHROPIC_API_KEY. "
            "Set ANTHROPIC_API_KEY, or switch OCR_BACKEND to trocr/tesseract."
        )

    try:
        import anthropic
    except ImportError as exc:
        raise ClaudeVisionError(
            "The 'anthropic' package is required for OCR_BACKEND=claude. "
            "Install it with: pip install anthropic"
        ) from exc

    kwargs: Dict[str, Any] = {
        # Generous per-request timeout; the Celery soft limit (540 s) is the
        # outer guard. SDK retries 429/5xx with backoff.
        "timeout": 240.0,
        "max_retries": 3,
        "api_key": api_key,
    }
    _client = anthropic.Anthropic(**kwargs)
    return _client


def reset_client_cache() -> None:
    """Test helper: drop the cached client so a fresh one is built."""
    global _client
    _client = None


# ── Image preparation ─────────────────────────────────────────────────────────

def _prepare_image(image_bytes: bytes, max_edge: Optional[int] = None) -> Tuple[str, str]:
    """
    Decode, optionally downscale to the model's max vision resolution, and
    re-encode as JPEG.

    Returns:
        (base64_data, media_type)

    Raises:
        ClaudeVisionError: if the bytes cannot be decoded as an image.
    """
    from PIL import Image

    limit = max_edge or settings.CLAUDE_OCR_MAX_IMAGE_EDGE
    try:
        img = Image.open(io.BytesIO(image_bytes))
        img.load()
    except Exception as exc:  # noqa: BLE001
        raise ClaudeVisionError(f"Cannot decode image for Claude OCR: {exc}") from exc

    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")

    long_edge = max(img.size)
    if long_edge > limit:
        scale = limit / long_edge
        new_size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
        img = img.resize(new_size, Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return base64.standard_b64encode(buf.getvalue()).decode("ascii"), "image/jpeg"


def _image_block(b64_data: str, media_type: str) -> Dict[str, Any]:
    return {
        "type": "image",
        "source": {"type": "base64", "media_type": media_type, "data": b64_data},
    }


# ── Response parsing ──────────────────────────────────────────────────────────

def _extract_json(response: Any) -> Dict[str, Any]:
    """Pull the JSON payload out of the first text block of a Message."""
    for block in response.content:
        if getattr(block, "type", None) == "text":
            try:
                return json.loads(block.text)
            except json.JSONDecodeError as exc:
                raise ClaudeVisionError(
                    f"Claude returned invalid JSON: {exc}"
                ) from exc
    raise ClaudeVisionError("Claude response contained no text block.")


def _clamp(value: Any, lo: float = 0.0, hi: float = 1.0) -> float:
    try:
        return min(hi, max(lo, float(value)))
    except (TypeError, ValueError):
        return 0.0


def parse_sheet_payload(payload: Dict[str, Any]) -> List[SheetMove]:
    """
    Convert the structured-output payload into validated SheetMove objects.

    Invalid entries (move_number < 1, bad color) are dropped with a warning
    rather than failing the whole sheet. Duplicate (move_number, color) cells
    keep the higher-confidence reading.
    """
    by_ply: Dict[int, SheetMove] = {}
    for raw in payload.get("moves", []):
        try:
            move_number = int(raw["move_number"])
            color = str(raw["color"])
            text = str(raw["text"]).strip()
        except (KeyError, TypeError, ValueError):
            logger.warning("Dropping malformed sheet move entry: %r", raw)
            continue
        if move_number < 1 or color not in ("white", "black") or not text:
            logger.warning("Dropping invalid sheet move entry: %r", raw)
            continue

        move = SheetMove(
            move_number=move_number,
            color=color,
            text=text,
            confidence=_clamp(raw.get("confidence")),
            alternates=tuple(
                str(a).strip() for a in raw.get("alternates", []) if str(a).strip()
            )[:3],
        )
        existing = by_ply.get(move.ply_index)
        if existing is None or move.confidence > existing.confidence:
            by_ply[move.ply_index] = move

    return [by_ply[p] for p in sorted(by_ply)]


def sheet_move_to_prediction(move: SheetMove, provider: str) -> OCRPrediction:
    """Convert a SheetMove into the standard OCRPrediction shape."""
    candidates = [OCRCandidate(text=move.text, confidence=move.confidence)]
    if move.alternates:
        # Alternates share the residual probability mass, decaying 2:1.
        residual = max(0.0, 1.0 - move.confidence)
        weights = [2 ** -(i + 1) for i in range(len(move.alternates))]
        total = sum(weights)
        for alt, w in zip(move.alternates, weights):
            candidates.append(
                OCRCandidate(text=alt, confidence=residual * w / total)
            )
    return OCRPrediction(raw_text=move.text, candidates=candidates, provider=provider)


def blank_prediction(provider: str) -> OCRPrediction:
    """Prediction representing an empty/unreadable cell."""
    return OCRPrediction(
        raw_text="",
        candidates=[OCRCandidate(text="", confidence=0.0)],
        provider=provider,
    )


# ── Provider ──────────────────────────────────────────────────────────────────

class ClaudeVisionProvider(OCRProvider):
    """
    OCR provider backed by the Claude API (vision + structured outputs).

    Preferred entry point is recognise_sheet() — one call per scoresheet.
    recognise_batch() exists for OCRProvider interface compatibility and
    sends crops as numbered images in chunked requests.
    """

    # Crops per request for recognise_batch (API limit is 100 images/request).
    BATCH_CHUNK_SIZE = 50

    @property
    def provider_name(self) -> str:
        return "claude_vision"

    # ── Full-sheet reading (preferred) ────────────────────────────────────────

    def recognise_sheet(self, image_bytes: bytes) -> List[SheetMove]:
        """
        Read every handwritten move from a full scoresheet photograph.

        Returns:
            SheetMove list sorted by ply_index (deduplicated per cell).

        Raises:
            ClaudeVisionError: on API failure, undecodable image, or
                unparseable response.
        """
        b64, media_type = _prepare_image(image_bytes)
        client = _get_client()

        try:
            response = client.messages.create(
                model=settings.CLAUDE_OCR_MODEL,
                max_tokens=8192,
                # No extended thinking: transcription is a perception task, and
                # adaptive thinking runs away — it consumed the entire token
                # budget on a full scoresheet and emitted no answer block,
                # causing "no text block" errors and a slow TrOCR fallback.
                system=_SHEET_SYSTEM_PROMPT,
                messages=[{
                    "role": "user",
                    "content": [
                        _image_block(b64, media_type),
                        {
                            "type": "text",
                            "text": (
                                "Transcribe every handwritten move on this "
                                "chess scoresheet."
                            ),
                        },
                    ],
                }],
                output_config={"format": {"type": "json_schema", "schema": _SHEET_SCHEMA}},
            )
        except ClaudeVisionError:
            raise
        except Exception as exc:  # noqa: BLE001 — anthropic.* errors + transport
            raise ClaudeVisionError(f"Claude OCR API call failed: {exc}") from exc

        payload = _extract_json(response)
        moves = parse_sheet_payload(payload)
        logger.info(
            "Claude sheet OCR: %d moves read (model=%s, input_tokens=%s, output_tokens=%s)",
            len(moves),
            settings.CLAUDE_OCR_MODEL,
            getattr(response.usage, "input_tokens", "?"),
            getattr(response.usage, "output_tokens", "?"),
        )
        return moves

    # ── Per-crop interface (OCRProvider contract) ─────────────────────────────

    def recognise_batch(self, images: List[bytes]) -> List[OCRPrediction]:
        if not images:
            raise ValueError("recognise_batch() called with an empty image list.")

        results: List[OCRPrediction] = []
        for start in range(0, len(images), self.BATCH_CHUNK_SIZE):
            chunk = images[start : start + self.BATCH_CHUNK_SIZE]
            results.extend(self._recognise_chunk(chunk))
        return results

    def _recognise_chunk(self, images: List[bytes]) -> List[OCRPrediction]:
        client = _get_client()

        content: List[Dict[str, Any]] = []
        decodable: List[bool] = []
        for img_bytes in images:
            try:
                b64, media_type = _prepare_image(img_bytes, max_edge=768)
                content.append(_image_block(b64, media_type))
                decodable.append(True)
            except ClaudeVisionError:
                # Substitute a 1×1 white pixel so indices stay aligned.
                content.append(_image_block(_BLANK_PIXEL_B64, "image/jpeg"))
                decodable.append(False)
        content.append({
            "type": "text",
            "text": f"Transcribe these {len(images)} chess move cells.",
        })

        try:
            response = client.messages.create(
                model=settings.CLAUDE_OCR_MODEL,
                max_tokens=8192,
                # No extended thinking — see recognise_sheet() for why.
                system=_BATCH_SYSTEM_PROMPT,
                messages=[{"role": "user", "content": content}],
                output_config={"format": {"type": "json_schema", "schema": _BATCH_SCHEMA}},
            )
        except Exception as exc:  # noqa: BLE001
            raise ClaudeVisionError(f"Claude OCR API call failed: {exc}") from exc

        payload = _extract_json(response)
        by_index: Dict[int, OCRPrediction] = {}
        for raw in payload.get("readings", []):
            try:
                idx = int(raw["image_index"])
            except (KeyError, TypeError, ValueError):
                continue
            if not (0 <= idx < len(images)):
                continue
            text = str(raw.get("text", "")).strip()
            if not text:
                by_index[idx] = blank_prediction(self.provider_name)
                continue
            move = SheetMove(
                move_number=1,
                color="white",
                text=text,
                confidence=_clamp(raw.get("confidence")),
                alternates=tuple(
                    str(a).strip() for a in raw.get("alternates", []) if str(a).strip()
                )[:3],
            )
            by_index[idx] = sheet_move_to_prediction(move, self.provider_name)

        return [
            by_index.get(i, blank_prediction(self.provider_name))
            if decodable[i] else blank_prediction(self.provider_name)
            for i in range(len(images))
        ]


# 1×1 white JPEG used to keep image indices aligned for undecodable crops.
_BLANK_PIXEL_B64 = (
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAACv/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AfwD/2Q=="
)


# ── Module-level singleton factory ────────────────────────────────────────────

_provider_instance: Optional[ClaudeVisionProvider] = None


def get_claude_provider() -> ClaudeVisionProvider:
    """Return the module-level ClaudeVisionProvider singleton."""
    global _provider_instance
    if _provider_instance is None:
        _provider_instance = ClaudeVisionProvider()
    return _provider_instance
