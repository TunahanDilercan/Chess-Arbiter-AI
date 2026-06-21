"""
Export confirmed (crop image, canonical SAN, locale) pairs from the live DB.

Every processed scoresheet leaves per-cell crop PNGs in storage plus a MoveEntry
whose `selected_san` is the validated move — either auto-accepted at high
confidence or fixed via the manual-correction flow. Those are reliable labels,
so the running app is effectively a labelled-data collector. This script pulls
them out for training/evaluation.

Reliability filter: is_legal AND selected_san present AND a crop exists AND
(not needs_review  OR  has at least one ReviewAction i.e. a human correction).

Split is BY GAME (never by cell) to avoid leakage. Real data is scarce and
precious, so by default everything goes to val/test (train stays synthetic);
override with --train-frac.

Run with the BACKEND environment (same .env / DB / storage as the app):
    python ml/data/export_labels.py --out ml/data/datasets/real
"""

from __future__ import annotations

import argparse
import asyncio
import json
import random
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List

_BACKEND = Path(__file__).resolve().parents[2] / "backend"
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))

from sqlalchemy import select  # noqa: E402
from sqlalchemy.orm import selectinload  # noqa: E402

from database import AsyncSessionLocal  # noqa: E402
from models.game import MoveEntry  # noqa: E402
from services.storage import get_storage  # noqa: E402


def is_reliable(entry: MoveEntry) -> bool:
    if not entry.is_legal or not entry.selected_san or entry.crop is None:
        return False
    corrected = len(entry.review_actions) > 0
    return (not entry.needs_review) or corrected


async def collect_rows() -> List[dict]:
    """Return [{game_id, ply, san, locale, key}] for every reliable entry."""
    storage = get_storage()
    rows: List[dict] = []
    async with AsyncSessionLocal() as session:
        stmt = (
            select(MoveEntry)
            .options(
                selectinload(MoveEntry.crop),
                selectinload(MoveEntry.game),
                selectinload(MoveEntry.review_actions),
            )
            .where(MoveEntry.is_legal.is_(True))
            .where(MoveEntry.selected_san.is_not(None))
        )
        entries = (await session.execute(stmt)).scalars().all()
        for e in entries:
            if not is_reliable(e):
                continue
            try:
                data = await storage.load(e.crop.crop_image_path)
            except Exception as exc:  # noqa: BLE001
                print(f"[skip] crop load failed for {e.id}: {exc}")
                continue
            rows.append({
                "game_id": e.game_id,
                "ply": e.ply_index,
                "san": e.selected_san,
                "locale": e.game.locale if e.game else "en",
                "bytes": data,
            })
    return rows


def split_by_game(
    rows: List[dict], rng: random.Random, train_frac: float, val_frac: float
) -> Dict[str, List[dict]]:
    by_game: Dict[str, List[dict]] = defaultdict(list)
    for r in rows:
        by_game[r["game_id"]].append(r)
    games = sorted(by_game)
    rng.shuffle(games)

    n = len(games)
    n_train = int(n * train_frac)
    n_val = int(n * val_frac)
    buckets = {
        "train": games[:n_train],
        "val": games[n_train:n_train + n_val],
        "test": games[n_train + n_val:],
    }
    out: Dict[str, List[dict]] = {}
    for name, gids in buckets.items():
        out[name] = [r for g in gids for r in by_game[g]]
    return out


def write_split(out_dir: Path, name: str, rows: List[dict]) -> int:
    if not rows:
        return 0
    split_dir = out_dir / name
    img_dir = split_dir / "images"
    img_dir.mkdir(parents=True, exist_ok=True)
    jsonl = split_dir / f"{name}.jsonl"
    with jsonl.open("w", encoding="utf-8") as fh:
        for i, r in enumerate(rows):
            rel = f"images/{r['game_id']}_{r['ply']:03d}.png"
            (split_dir / rel).write_bytes(r["bytes"])
            fh.write(json.dumps({
                "image": rel,
                "text": r["san"],
                "locale": r["locale"],
                "source": "real",
            }) + "\n")
    return len(rows)


async def main_async(args: argparse.Namespace) -> None:
    rng = random.Random(args.seed)
    rows = await collect_rows()
    print(f"[info] {len(rows)} reliable labelled crops collected.")
    if not rows:
        print("[info] Nothing to export yet — process some scoresheets first.")
        return

    splits = split_by_game(rows, rng, args.train_frac, args.val_frac)
    out_dir = Path(args.out)
    for name in ("train", "val", "test"):
        count = write_split(out_dir, name, splits.get(name, []))
        print(f"  {name}: {count} samples")
    print(f"[done] exported to {out_dir}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Export confirmed crops+labels from the DB")
    ap.add_argument("--out", default="ml/data/datasets/real")
    ap.add_argument("--train-frac", type=float, default=0.0,
                    help="fraction of GAMES for train (default 0 — keep real data for eval)")
    ap.add_argument("--val-frac", type=float, default=0.5)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
