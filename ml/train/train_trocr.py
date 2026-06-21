"""
Fine-tune TrOCR for handwritten chess-move recognition.

Input: jsonl datasets produced by ml/data/synth_generator.py and
ml/data/export_labels.py (each line: {"image": rel, "text": canonical_san, ...}).
Output: a fine-tuned VisionEncoderDecoderModel checkpoint that drops straight into
the backend's TrOCRProvider via TROCR_MODEL_ID.

The label is canonical English SAN regardless of the handwriting locale, so the
model learns recognition + locale translation in one step.

Run (in the ml venv, on the GPU box):
    python ml/train/train_trocr.py --config ml/train/config.yaml

Requires: torch (CUDA build), transformers, datasets-free (custom Dataset),
jiwer for CER. See ml/requirements.txt.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List

import torch
import yaml
from PIL import Image
from torch.utils.data import Dataset
from transformers import (
    EarlyStoppingCallback,
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
    TrOCRProcessor,
    VisionEncoderDecoderModel,
)

try:
    from jiwer import cer as _cer
except ImportError:  # pragma: no cover - clear runtime guidance
    _cer = None


# ── Dataset ────────────────────────────────────────────────────────────────────


class MoveOCRDataset(Dataset):
    """Reads one or more jsonl files; yields pixel_values + tokenised labels."""

    def __init__(self, jsonl_paths: List[str], processor: TrOCRProcessor, max_len: int):
        self.processor = processor
        self.max_len = max_len
        self.samples: List[Dict[str, Any]] = []
        for jp in jsonl_paths:
            base = Path(jp).parent
            with open(jp, encoding="utf-8") as fh:
                for line in fh:
                    rec = json.loads(line)
                    rec["_path"] = base / rec["image"]
                    self.samples.append(rec)

    def __len__(self) -> int:
        return len(self.samples)

    def __getitem__(self, idx: int) -> Dict[str, Any]:
        rec = self.samples[idx]
        image = Image.open(rec["_path"]).convert("RGB")
        pixel_values = self.processor(images=image, return_tensors="pt").pixel_values[0]
        labels = self.processor.tokenizer(
            rec["text"],
            padding="max_length",
            max_length=self.max_len,
            truncation=True,
        ).input_ids
        # Ignore pad tokens in the loss.
        pad_id = self.processor.tokenizer.pad_token_id
        labels = [t if t != pad_id else -100 for t in labels]
        return {"pixel_values": pixel_values, "labels": torch.tensor(labels)}


# ── Training ───────────────────────────────────────────────────────────────────


def load_config(path: str) -> Dict[str, Any]:
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def build_compute_metrics(processor: TrOCRProcessor):
    def compute_metrics(pred) -> Dict[str, float]:
        label_ids = pred.label_ids
        pred_ids = pred.predictions
        label_ids = [[t for t in seq if t != -100] for seq in label_ids]
        pred_str = processor.tokenizer.batch_decode(pred_ids, skip_special_tokens=True)
        label_str = processor.tokenizer.batch_decode(label_ids, skip_special_tokens=True)
        pred_str = [s.strip() for s in pred_str]
        label_str = [s.strip() for s in label_str]

        exact = sum(p == l for p, l in zip(pred_str, label_str)) / max(len(label_str), 1)
        metrics = {"exact_move": exact}
        if _cer is not None:
            metrics["cer"] = float(_cer(label_str, pred_str))
        return metrics

    return compute_metrics


def main() -> None:
    ap = argparse.ArgumentParser(description="Fine-tune TrOCR on handwritten chess moves")
    ap.add_argument("--config", default="ml/train/config.yaml")
    args = ap.parse_args()
    cfg = load_config(args.config)

    torch.manual_seed(cfg.get("seed", 42))
    device = "cuda" if torch.cuda.is_available() else "cpu"

    processor = TrOCRProcessor.from_pretrained(cfg["model_id"])
    model = VisionEncoderDecoderModel.from_pretrained(cfg["model_id"])

    # Decoder/generation config required for VisionEncoderDecoder fine-tuning.
    model.config.decoder_start_token_id = processor.tokenizer.cls_token_id
    model.config.pad_token_id = processor.tokenizer.pad_token_id
    model.config.vocab_size = model.config.decoder.vocab_size
    model.config.eos_token_id = processor.tokenizer.sep_token_id
    model.config.max_length = cfg["max_target_length"]
    model.config.num_beams = cfg.get("num_beams", 3)

    train_ds = MoveOCRDataset(cfg["train"], processor, cfg["max_target_length"])
    val_path = cfg.get("val")
    val_ds = (
        MoveOCRDataset([val_path], processor, cfg["max_target_length"])
        if val_path and Path(val_path).exists()
        else None
    )
    print(f"[info] train={len(train_ds)} val={len(val_ds) if val_ds else 0} device={device}")

    targs = Seq2SeqTrainingArguments(
        output_dir=cfg["output_dir"],
        per_device_train_batch_size=cfg["batch_size"],
        per_device_eval_batch_size=cfg["batch_size"],
        gradient_accumulation_steps=cfg.get("grad_accum", 1),
        learning_rate=float(cfg["lr"]),
        warmup_ratio=cfg.get("warmup_ratio", 0.1),
        weight_decay=cfg.get("weight_decay", 0.01),
        num_train_epochs=cfg["epochs"],
        predict_with_generate=True,
        fp16=cfg.get("fp16", True) and device == "cuda",
        eval_strategy="steps" if val_ds else "no",
        eval_steps=cfg.get("eval_steps", 500),
        save_steps=cfg.get("eval_steps", 500),
        save_total_limit=cfg.get("save_total_limit", 2),
        load_best_model_at_end=bool(val_ds),
        metric_for_best_model="cer" if _cer is not None else "exact_move",
        greater_is_better=False if _cer is not None else True,
        logging_steps=50,
        seed=cfg.get("seed", 42),
        report_to=[],
    )

    callbacks = []
    if val_ds:
        callbacks.append(
            EarlyStoppingCallback(early_stopping_patience=cfg.get("early_stopping_patience", 4))
        )

    trainer = Seq2SeqTrainer(
        model=model,
        args=targs,
        train_dataset=train_ds,
        eval_dataset=val_ds,
        data_collator=None,  # tensors are uniform (max_length padding)
        compute_metrics=build_compute_metrics(processor) if val_ds else None,
        callbacks=callbacks,
    )

    trainer.train()

    best = Path(cfg["output_dir"]) / "best"
    trainer.save_model(str(best))
    processor.save_pretrained(str(best))
    print(f"[done] saved best model -> {best}")
    print(f"       backend: set TROCR_MODEL_ID={best.resolve()} and OCR_BACKEND=trocr")


if __name__ == "__main__":
    main()
