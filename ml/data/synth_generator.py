"""
Synthetic handwritten chess-move generator.

Produces (image, canonical-SAN, locale) training samples by:
  1. Sampling canonical SAN moves (random legal games + explicit castling/
     promotion coverage) via python-chess.
  2. Rendering each move as a handwriting string. For non-English locales the
     uppercase piece letters are remapped to that locale's notation (e.g. TR
     "Nf3" is written "Af3") using the backend's LOCALE_PIECE_MAPS — inverted.
  3. Augmenting the rendered cell to look like a real scoresheet crop (rotation,
     ink thickness, paper noise, grid-line bleed, blur, contrast jitter).

The label written to the jsonl is always the CANONICAL English SAN, so it matches
the backend's `MoveEntry.selected_san` and `candidate_matcher` expectations.

Usage:
    python ml/data/synth_generator.py --n 20000 --locales tr en \
        --fonts-dir ml/data/fonts --out ml/data/datasets/synth
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path
from typing import Dict, List

import chess
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ── Reuse the backend's locale piece maps (single source of truth) ─────────────
_BACKEND = Path(__file__).resolve().parents[2] / "backend"
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))
from services.chess.normalizer import LOCALE_PIECE_MAPS  # noqa: E402


def inverse_piece_map(locale: str) -> Dict[str, str]:
    """canonical English piece letter → locale letter (inverse of normalizer map).

    LOCALE_PIECE_MAPS is locale→English; inverting is safe because each locale
    map is 1:1 (e.g. TR: Ş→K, V→Q, K→R, F→B, A→N inverts to K→Ş, Q→V, R→K, ...).
    """
    fwd = LOCALE_PIECE_MAPS.get(locale, {})
    return {english: local for local, english in fwd.items()}


def to_locale_notation(canonical_san: str, locale: str) -> str:
    """Render a canonical SAN in the given locale's piece letters.

    Only uppercase piece letters (K Q R B N) are remapped; files, ranks, 'x',
    '+', '#', '=', and castling 'O' are left untouched.
    """
    inv = inverse_piece_map(locale)
    if not inv:
        return canonical_san
    return "".join(inv.get(ch, ch) for ch in canonical_san)


# ── Move sampling ──────────────────────────────────────────────────────────────


def sample_game_sans(rng: random.Random, max_plies: int = 60) -> List[str]:
    """Play one random legal game; return the canonical SAN of every move."""
    board = chess.Board()
    sans: List[str] = []
    for _ in range(max_plies):
        if board.is_game_over():
            break
        move = rng.choice(list(board.legal_moves))
        sans.append(board.san(move))  # SAN includes x, +, # automatically
        board.push(move)
    return sans


def explicit_special_sans(rng: random.Random, count: int) -> List[str]:
    """Castling and promotion SANs, under-represented in short random games."""
    out: List[str] = []
    files = "abcdefgh"
    pieces = ["Q", "R", "B", "N"]
    for _ in range(count):
        kind = rng.random()
        if kind < 0.35:
            out.append(rng.choice(["O-O", "O-O-O"]))
        else:
            # Promotion: white to rank 8 or black to rank 1, with/without capture.
            f = rng.choice(files)
            rank = rng.choice("18")
            piece = rng.choice(pieces)
            if rng.random() < 0.4:  # capture-promotion (e.g. exd8=Q)
                cap = rng.choice([c for c in files if c != f])
                san = f"{f}x{cap}{rank}={piece}"
            else:
                san = f"{f}{rank}={piece}"
            if rng.random() < 0.2:
                san += rng.choice(["+", "#"])
            out.append(san)
    return out


def build_move_pool(rng: random.Random, target: int) -> List[str]:
    """Assemble a deduplicated-ish pool of canonical SANs to sample from."""
    pool: List[str] = []
    while len(pool) < target:
        pool.extend(sample_game_sans(rng))
    pool.extend(explicit_special_sans(rng, max(target // 10, 50)))
    rng.shuffle(pool)
    return pool


# ── Rendering + augmentation ────────────────────────────────────────────────────


def load_fonts(fonts_dir: Path) -> List[Path]:
    fonts = sorted(
        [p for p in fonts_dir.glob("*.ttf")] + [p for p in fonts_dir.glob("*.otf")]
    )
    return fonts


def render_text(text: str, font_path: Path | None, rng: random.Random) -> np.ndarray:
    """Render `text` in a handwriting font onto a white canvas; return BGR ndarray."""
    size = rng.randint(40, 64)
    if font_path is not None:
        font = ImageFont.truetype(str(font_path), size)
    else:
        font = ImageFont.load_default()  # smoke-test fallback (not handwriting)

    # Measure and pad generously so later rotation/shift doesn't clip.
    tmp = Image.new("RGB", (10, 10), "white")
    bbox = ImageDraw.Draw(tmp).textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad = int(size * 0.6)
    img = Image.new("RGB", (tw + 2 * pad, th + 2 * pad), "white")
    draw = ImageDraw.Draw(img)
    ink = rng.randint(0, 60)  # near-black ink with slight variation
    draw.text((pad - bbox[0], pad - bbox[1]), text, font=font, fill=(ink, ink, ink))
    return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2BGR)


def augment(img: np.ndarray, rng: random.Random) -> np.ndarray:
    """Apply scoresheet-like distortions. Input/output BGR uint8."""
    h, w = img.shape[:2]

    # Rotation + slight shear (handwriting slant / scan skew)
    angle = rng.uniform(-5, 5)
    M = cv2.getRotationMatrix2D((w / 2, h / 2), angle, 1.0)
    M[0, 1] += rng.uniform(-0.10, 0.10)  # horizontal shear
    img = cv2.warpAffine(img, M, (w, h), borderValue=(255, 255, 255))

    # Ink thickness: dilate (thicker pen) or erode (thin/faded)
    if rng.random() < 0.6:
        k = np.ones((rng.randint(1, 3), rng.randint(1, 3)), np.uint8)
        if rng.random() < 0.5:
            img = cv2.erode(img, k)   # erode on white bg thickens dark ink
        else:
            img = cv2.dilate(img, k)  # dilate thins dark ink

    # Grid-line bleed: a faint horizontal or vertical line from the cell border
    if rng.random() < 0.4:
        gray = rng.randint(120, 200)
        if rng.random() < 0.5:
            y = rng.choice([rng.randint(0, 3), h - 1 - rng.randint(0, 3)])
            cv2.line(img, (0, y), (w, y), (gray, gray, gray), 1)
        else:
            x = rng.choice([rng.randint(0, 3), w - 1 - rng.randint(0, 3)])
            cv2.line(img, (x, 0), (x, h), (gray, gray, gray), 1)

    # Paper noise
    if rng.random() < 0.7:
        noise = rng.uniform(3, 14)
        img = np.clip(
            img.astype(np.float32) + np.random.normal(0, noise, img.shape),
            0, 255,
        ).astype(np.uint8)

    # Mild blur (scan softness)
    if rng.random() < 0.4:
        img = cv2.GaussianBlur(img, (3, 3), 0)

    # Contrast / brightness jitter
    if rng.random() < 0.5:
        alpha = rng.uniform(0.85, 1.2)   # contrast
        beta = rng.uniform(-15, 15)      # brightness
        img = cv2.convertScaleAbs(img, alpha=alpha, beta=beta)

    # Normalise height to ~64px (keep aspect), like a cell crop
    target_h = 64
    scale = target_h / img.shape[0]
    img = cv2.resize(img, (max(int(img.shape[1] * scale), 8), target_h))
    return img


# ── Main ─────────────────────────────────────────────────────────────────────


def main() -> None:
    ap = argparse.ArgumentParser(description="Synthetic handwritten chess-move generator")
    ap.add_argument("--n", type=int, default=20000, help="number of samples")
    ap.add_argument("--locales", nargs="+", default=["tr", "en"])
    ap.add_argument("--fonts-dir", default="ml/data/fonts")
    ap.add_argument("--out", default="ml/data/datasets/synth")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    np.random.seed(args.seed)

    out = Path(args.out)
    img_dir = out / "images"
    img_dir.mkdir(parents=True, exist_ok=True)

    fonts = load_fonts(Path(args.fonts_dir))
    if not fonts:
        print(
            f"[warn] No .ttf/.otf fonts in {args.fonts_dir!r}. Falling back to PIL's "
            "default bitmap font - fine for a smoke test, NOT for real training. "
            "Add handwriting fonts (Caveat, Patrick Hand, Reenie Beanie, ...)."
        )

    pool = build_move_pool(rng, target=args.n)
    jsonl_path = out / "train.jsonl"
    written = 0
    with jsonl_path.open("w", encoding="utf-8") as fh:
        for i in range(args.n):
            canonical = pool[i % len(pool)]
            locale = rng.choice(args.locales)
            display = to_locale_notation(canonical, locale)
            font_path = rng.choice(fonts) if fonts else None
            img = augment(render_text(display, font_path, rng), rng)

            rel = f"images/{i:06d}.png"
            cv2.imwrite(str(out / rel), img)
            fh.write(json.dumps({
                "image": rel,
                "text": canonical,
                "locale": locale,
                "source": "synth",
            }) + "\n")
            written += 1
            if written % 2000 == 0:
                print(f"  {written}/{args.n}")

    print(f"[done] {written} samples -> {jsonl_path}")


if __name__ == "__main__":
    main()
