# Arbiter AI — Architecture Reference

## System Overview

```
[Flutter App]
    │
    ├─ POST /upload  ──────────────────► [FastAPI]
    │                                        │
    ├─ GET /sse/{job_id} ◄──────────────     ├─ Creates Job → Celery queue
    │   (streaming status)                   │
    │                                        ▼
    └─ GET /games/{id} ◄─────────────── [Celery Worker]
         (final result)                      ├─ OpenCV preprocessing
                                             ├─ Grid detection + crop
                                             ├─ TrOCR per cell (top-3)
                                             ├─ Normalization
                                             ├─ Legal move matching
                                             ├─ FIDE analysis
                                             └─ Store results → PostgreSQL
```

## Data Flow Per Move

```
Raw crop image
    → TrOCR → ["Bxh6" 0.91, "Bh6" 0.06, "Bxg7" 0.03]
    → Normalizer → "Bxh6"
    → python-chess board.legal_moves → ["Bxh6", "Bxf8", ...]
    → Levenshtein match → confidence 0.91
    → if >= 0.85: auto-accept → selected_san = "Bxh6"
    → if < 0.85: needs_manual_review = true → pause, show to user
    → fide_analyzer.check(board) → fide_alerts = []
    → advance board state
```

## SSE Event Sequence

```
job created     → { "status": "queued" }
CV starts       → { "status": "preprocessing" }
OCR starts      → { "status": "ocr", "progress": 0.3 }
Analysis starts → { "status": "analyzing" }
Done            → { "status": "completed", "game_id": "uuid" }
Error           → { "status": "failed", "error": "..." }
```

## Manual Correction Flow

```
User sees illegal/uncertain move at ply N
    → Correction modal opens
    → Shows: board before move, crop image, OCR text, legal candidates
    → User enters corrected SAN via chess keyboard
    → POST /games/{id}/moves/{N}/correct { "san": "Nf3" }
    → Backend re-runs analysis from ply N onward
    → Returns updated game JSON
    → Flutter updates replay from ply N
```

## Database Entities

```
Game           → id, session_id, status, pgn, created_at
UploadedAsset  → id, game_id, file_path, file_type
ProcessingJob  → id, game_id, status, celery_task_id
MoveEntry      → id, game_id, ply_index, color, selected_san,
                 selected_uci, is_legal, confidence, needs_review
MoveCrop       → id, move_entry_id, crop_image_path
OCRResult      → id, move_entry_id, raw_text, candidates_json, normalized_text
RuleFinding    → id, game_id, ply_index, type, description, is_automatic
ReviewAction   → id, move_entry_id, original_san, corrected_san, corrected_at
ExportArtifact → id, game_id, format, file_path, created_at
```

## Per-Move JSON Schema

```json
{
  "move_number": 14,
  "ply_index": 27,
  "color": "white",
  "ocr_raw_text": "Bxh6",
  "ocr_candidates": [
    {"text": "Bxh6", "confidence": 0.91},
    {"text": "Bh6",  "confidence": 0.06},
    {"text": "Bxg7", "confidence": 0.03}
  ],
  "normalized_text": "Bxh6",
  "selected_san": "Bxh6",
  "selected_uci": "g5h6",
  "fen_before": "...",
  "fen_after": "...",
  "is_legal": true,
  "needs_manual_review": false,
  "confidence": 0.91,
  "fide_alerts": ["threefold_claim_available"],
  "crop_image_url": "..."
}
```
