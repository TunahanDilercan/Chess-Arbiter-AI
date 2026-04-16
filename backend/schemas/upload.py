"""
Pydantic v2 schemas for the upload and job-status flows.

These complement schemas/analysis.py (which owns GameAnalysisResponse).
"""

from __future__ import annotations

from typing import Optional

from pydantic import BaseModel, Field


# ── Upload response ───────────────────────────────────────────────────────────


class UploadResponse(BaseModel):
    """
    Returned immediately after POST /api/upload.

    The client should subscribe to sse_url to track job progress.
    When status_url returns status='completed', fetch game_url for the full result.
    """

    game_id: str
    job_id: str
    status: str = Field(
        description="Initial job status, always 'queued' at upload time."
    )
    sse_url: str = Field(
        description="SSE endpoint to subscribe for real-time job progress (Phase 7+)."
    )
    game_url: str = Field(
        description="URL to fetch the full annotated game result when complete."
    )

    model_config = {
        "json_schema_extra": {
            "example": {
                "game_id": "3f7a9b2e-1234-4abc-8def-000000000001",
                "job_id": "9c8b7a6e-5d4c-3b2a-1f0e-000000000002",
                "status": "queued",
                "sse_url": "/api/sse/9c8b7a6e-5d4c-3b2a-1f0e-000000000002",
                "game_url": "/api/games/3f7a9b2e-1234-4abc-8def-000000000001",
            }
        }
    }


# ── Job status ────────────────────────────────────────────────────────────────


class JobStatus(BaseModel):
    """Snapshot of a processing job — used by the SSE event payload (Phase 7+)."""

    job_id: str
    game_id: str
    status: str
    error_message: Optional[str] = None


# ── Game summary ──────────────────────────────────────────────────────────────


class GameSummary(BaseModel):
    """
    Lightweight game record for list endpoints.
    Does not include move-level detail.
    """

    game_id: str
    session_id: str
    status: str
    locale: str
    created_at: str
    total_moves: Optional[int] = None
    has_findings: Optional[bool] = None
    upload_filename: Optional[str] = None
