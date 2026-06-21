"""
Evaluate a fine-tuned chess-move TrOCR checkpoint on a labelled jsonl set.

Cell-level metrics (this script):
  - CER            character error rate of the top-1 prediction
  - exact_move     top-1 prediction equals the canonical SAN label
  - top3_move      label appears in the top-N beam hypotheses
                   (N defaults to 3, matching backend TROCR_NUM_CANDIDATES)
  - per-locale breakdown (tr/en/...)

NOTE on end-to-end "legal-match": matching a read against the *legal moves of the
position* (via candidate_matcher) needs full board context, which a per-cell
dataset doesn't carry. That metric is measured separately by running a whole
scoresheet through the backend pipeline (see ml/README.md, Faz 1). Keeping it out
of here avoids reporting a circular/fake number.

Run:
    python ml/eval/evaluate.py --checkpoint ml/checkpoints/run1/best \
        --data ml/data/datasets/real/test/test.jsonl
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Dict, List

import torch
from PIL import Image
from transformers import TrOCRProcessor, VisionEncoderDecoderModel

try:
    from jiwer import cer as _cer
except ImportError:
    _cer = None


def load_records(jsonl: str) -> List[dict]:
    base = Path(jsonl).parent
    recs = []
    with open(jsonl, encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            r["_path"] = base / r["image"]
            recs.append(r)
    return recs


@torch.no_grad()
def predict_topk(
    model, processor, images: List[Image.Image], k: int, device: str
) -> List[List[str]]:
    """Return top-k decoded strings (best-first) for each image."""
    pixel_values = processor(images=images, return_tensors="pt").pixel_values.to(device)
    out = model.generate(
        pixel_values,
        num_beams=max(k, 3),
        num_return_sequences=k,
        max_new_tokens=16,
    )
    texts = processor.tokenizer.batch_decode(out, skip_special_tokens=True)
    texts = [t.strip() for t in texts]
    # Reshape flat [n*k] back into n lists of k.
    return [texts[i * k:(i + 1) * k] for i in range(len(images))]


def main() -> None:
    ap = argparse.ArgumentParser(description="Evaluate a chess-move TrOCR checkpoint")
    ap.add_argument("--checkpoint", required=True)
    ap.add_argument("--data", required=True, help="test jsonl")
    ap.add_argument("--num-candidates", type=int, default=3)
    ap.add_argument("--batch-size", type=int, default=16)
    args = ap.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    processor = TrOCRProcessor.from_pretrained(args.checkpoint)
    model = VisionEncoderDecoderModel.from_pretrained(args.checkpoint).to(device).eval()

    recs = load_records(args.data)
    if not recs:
        print("[info] empty dataset — nothing to evaluate.")
        return

    n = len(recs)
    exact = 0
    topk_hits = 0
    preds_top1: List[str] = []
    labels: List[str] = []
    per_locale: Dict[str, List[int]] = defaultdict(lambda: [0, 0])  # locale -> [hits, total]

    for start in range(0, n, args.batch_size):
        batch = recs[start:start + args.batch_size]
        images = [Image.open(r["_path"]).convert("RGB") for r in batch]
        topk = predict_topk(model, processor, images, args.num_candidates, device)
        for r, cand in zip(batch, topk):
            label = r["text"].strip()
            labels.append(label)
            preds_top1.append(cand[0] if cand else "")
            if cand and cand[0] == label:
                exact += 1
            if label in cand:
                topk_hits += 1
                per_locale[r.get("locale", "?")][0] += 1
            per_locale[r.get("locale", "?")][1] += 1
        print(f"  {min(start + args.batch_size, n)}/{n}")

    print("\n=== Results ===")
    print(f"samples       : {n}")
    print(f"exact_move    : {exact / n:.4f}")
    print(f"top{args.num_candidates}_move     : {topk_hits / n:.4f}")
    if _cer is not None:
        print(f"CER (top-1)   : {float(_cer(labels, preds_top1)):.4f}")
    else:
        print("CER           : (install jiwer for CER)")
    print("\nper-locale top-k:")
    for loc, (hits, total) in sorted(per_locale.items()):
        print(f"  {loc}: {hits}/{total} = {hits / max(total, 1):.4f}")


if __name__ == "__main__":
    main()
