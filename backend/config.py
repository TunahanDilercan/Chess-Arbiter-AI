from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    # ── API ────────────────────────────────────────────────────────────────────
    APP_TITLE: str = "Arbiter AI"
    APP_VERSION: str = "0.3.0"
    DEBUG: bool = False

    # ── CORS ──────────────────────────────────────────────────────────────────
    CORS_ORIGINS: List[str] = ["*"]

    # ── Chess analysis ─────────────────────────────────────────────────────────
    OCR_CONFIDENCE_THRESHOLD: float = 0.85

    # ── Database ───────────────────────────────────────────────────────────────
    DATABASE_URL: str = "postgresql+asyncpg://arbiter:arbiter@localhost:5432/arbiter"

    # ── Redis / Celery ─────────────────────────────────────────────────────────
    REDIS_URL: str = "redis://localhost:6379/0"

    # ── Storage ────────────────────────────────────────────────────────────────
    STORAGE_BACKEND: str = "local"
    LOCAL_STORAGE_PATH: str = "./storage"
    S3_BUCKET: str = ""
    S3_REGION: str = "us-east-1"

    # ── Upload validation ──────────────────────────────────────────────────────
    MAX_UPLOAD_SIZE_MB: int = 20

    # ── Security ───────────────────────────────────────────────────────────────
    # Per-IP fixed-window rate limits (requests per minute).
    RATE_LIMIT_ENABLED: bool = True
    RATE_LIMIT_PER_MINUTE: int = 120
    RATE_LIMIT_UPLOADS_PER_MINUTE: int = 10

    # Trust X-Forwarded-For for client IPs. Enable ONLY when the app is
    # reachable exclusively through a reverse proxy that sets the header.
    TRUST_PROXY_HEADERS: bool = False

    # Emit Strict-Transport-Security. Enable when serving over HTTPS.
    ENABLE_HSTS: bool = False

    # ── CV / Grid detection ────────────────────────────────────────────────────
    # Minimum number of data rows a detected grid must contain.
    # Below this the scoresheet is considered unreadable and the job fails.
    CV_MIN_ROWS: int = 3

    # Grid detection confidence threshold [0.0, 1.0].
    # Below this the detection is considered too uncertain to proceed.
    CV_CONFIDENCE_THRESHOLD: float = 0.55

    # Fraction of white pixels above which a cell is considered blank.
    # Blank cells are skipped — no crop, no OCR, no MoveEntry.
    CV_BLANK_CELL_THRESHOLD: float = 0.97

    # Number of header rows at the top of the detected grid to skip.
    # Standard scoresheets have 1 header row ("No. | White | Black").
    CV_HEADER_ROWS: int = 1

    # ── OCR ────────────────────────────────────────────────────────────────────
    # Model name passed to TrOCRProcessor.from_pretrained / VisionEncoderDecoderModel.from_pretrained.
    TROCR_MODEL_ID: str = "microsoft/trocr-large-handwritten"

    # Maximum number of crop images sent in a single forward pass.
    # Reduce if the worker machine is memory-constrained.
    TROCR_MAX_BATCH_SIZE: int = 32

    # Number of beam-search candidates returned per move cell.
    # Must be ≥ 1.  Higher values give the candidate_matcher more options
    # but increase inference time linearly.
    TROCR_NUM_CANDIDATES: int = 3

    # Active OCR backend:
    #   "claude"    — Claude Vision API, full-sheet reading (production, highest accuracy)
    #   "trocr"     — local TrOCR model (offline fallback)
    #   "tesseract" — dev/comparison only
    OCR_BACKEND: str = "claude"

    # ── Claude Vision OCR ──────────────────────────────────────────────────────
    # API key for the Anthropic API. Empty string → SDK falls back to the
    # ANTHROPIC_API_KEY environment variable.
    ANTHROPIC_API_KEY: str = ""

    # Model used for scoresheet reading.
    CLAUDE_OCR_MODEL: str = "claude-opus-4-8"

    # Longest image edge sent to the API. 2576 px is the model's maximum
    # vision resolution — larger inputs gain nothing and cost more.
    CLAUDE_OCR_MAX_IMAGE_EDGE: int = 2576

    # If the Claude API call fails (network, auth, quota), fall back to the
    # local TrOCR model instead of failing the job.
    OCR_FALLBACK_TO_TROCR: bool = True

    # ── Dev helpers ────────────────────────────────────────────────────────────
    AUTO_CREATE_TABLES: bool = True

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
