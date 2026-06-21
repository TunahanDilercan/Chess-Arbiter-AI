# Backend — Claude Code Context

## Stack
Python 3.11, FastAPI, python-chess, OpenCV, Claude Vision OCR (TrOCR fallback), Celery, Redis, PostgreSQL, SQLAlchemy, Pydantic v2, Alembic

## Module Map
```
backend/
├── main.py                  # FastAPI app entry, router registration
├── config.py                # Settings via pydantic-settings
├── database.py              # SQLAlchemy engine + session
├── models/                  # SQLAlchemy ORM models
├── schemas/                 # Pydantic request/response schemas
├── api/routes/
│   ├── upload.py            # POST /upload
│   ├── games.py             # GET /games/{id}
│   ├── review.py            # POST /games/{id}/moves/{ply}/correct
│   └── sse.py               # GET /sse/{job_id}
├── services/
│   ├── chess/
│   │   ├── chess_service.py      # Board simulation, legal moves
│   │   ├── fide_analyzer.py      # FIDE draw/termination checks
│   │   ├── normalizer.py         # OCR text normalization
│   │   └── candidate_matcher.py  # Levenshtein + confidence scoring
│   ├── cv/
│   │   ├── preprocessor.py       # Grayscale, denoise, threshold
│   │   ├── grid_detector.py      # Adaptive grid detection
│   │   └── crop_extractor.py     # Move cell cropping
│   ├── ocr/
│   │   ├── base.py               # OCRProvider abstract interface
│   │   ├── claude_vision.py      # Claude Vision full-sheet OCR (default)
│   │   ├── trocr.py              # TrOCR implementation (fallback)
│   │   └── tesseract.py          # Tesseract (dev/comparison only)
│   ├── storage.py                # Local dev / S3 interface
│   └── job_service.py            # Job creation and status
└── workers/
    ├── celery_app.py
    └── processing_tasks.py
```

## Critical Rules
- chess_service.py and fide_analyzer.py are the source of truth — no chess logic elsewhere
- OCRProvider must be used via the abstract base, never instantiate TrOCR directly in routes
- All background work goes through Celery tasks — no blocking in route handlers
- Every new FIDE check must specify if it's AUTOMATIC or CLAIMABLE in a comment

## Python Style
- Type hints on every function signature
- Pydantic v2 models for all API inputs/outputs
- SQLAlchemy 2.0 style (select(), not query())
- Async route handlers where I/O is involved
- Never use bare `except:` — catch specific exceptions

## Test Commands
```bash
pytest tests/ -v
pytest tests/chess/ -v          # chess logic tests only
pytest tests/ -k "fide"         # FIDE rule tests only
```

## Key Dependencies
```
fastapi, uvicorn, python-chess, opencv-python-headless,
transformers, torch, celery, redis, sqlalchemy, alembic,
pydantic-settings, python-levenshtein, Pillow, boto3
```

## Confidence Threshold
OCR auto-accept threshold: 0.85 (configurable via config.py)
Below threshold → needs_manual_review = True
