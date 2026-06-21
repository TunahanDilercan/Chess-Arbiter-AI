"""
SQLAlchemy 2.0 ORM models — complete data model for Arbiter AI.

All UUIDs are stored as VARCHAR(50) strings for cross-database compatibility
(PostgreSQL in production, SQLite in tests).

Table dependency order (no forward refs needed if defined top-to-bottom):
  games
    ↳ uploaded_assets
    ↳ processing_jobs
    ↳ move_entries
        ↳ move_crops
        ↳ ocr_results
        ↳ review_actions
    ↳ rule_findings
    ↳ export_artifacts
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    JSON,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from models.base import Base


def _uuid() -> str:
    return str(uuid.uuid4())


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Game ──────────────────────────────────────────────────────────────────────


class Game(Base):
    __tablename__ = "games"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    session_id: Mapped[str] = mapped_column(String(50), nullable=False, index=True)

    # GameStatus enum value stored as string
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")

    # Set after Phase 3+ analysis completes
    pgn: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    failure_point_ply: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Locale used for normalizer (stored so re-analysis uses same locale)
    locale: Mapped[str] = mapped_column(String(10), nullable=False, default="en")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now, onupdate=_now
    )

    # Relationships
    uploaded_asset: Mapped[Optional[UploadedAsset]] = relationship(
        back_populates="game", uselist=False, cascade="all, delete-orphan"
    )
    processing_job: Mapped[Optional[ProcessingJob]] = relationship(
        back_populates="game", uselist=False, cascade="all, delete-orphan"
    )
    move_entries: Mapped[List[MoveEntry]] = relationship(
        back_populates="game",
        order_by="MoveEntry.ply_index",
        cascade="all, delete-orphan",
    )
    rule_findings: Mapped[List[RuleFindingDB]] = relationship(
        back_populates="game",
        order_by="RuleFindingDB.ply_index",
        cascade="all, delete-orphan",
    )
    export_artifacts: Mapped[List[ExportArtifact]] = relationship(
        back_populates="game", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Game id={self.id!r} status={self.status!r}>"


# ── UploadedAsset ─────────────────────────────────────────────────────────────


class UploadedAsset(Base):
    __tablename__ = "uploaded_assets"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    game_id: Mapped[str] = mapped_column(
        String(50), ForeignKey("games.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # Path relative to storage root (works for both local and S3 key)
    file_path: Mapped[str] = mapped_column(String(512), nullable=False)

    # MIME type: image/jpeg, image/png, image/webp, application/pdf
    file_type: Mapped[str] = mapped_column(String(64), nullable=False)

    original_filename: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
    file_size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now
    )

    game: Mapped[Game] = relationship(back_populates="uploaded_asset")

    def __repr__(self) -> str:
        return f"<UploadedAsset id={self.id!r} file_type={self.file_type!r}>"


# ── ProcessingJob ─────────────────────────────────────────────────────────────


class ProcessingJob(Base):
    """
    Tracks the lifecycle of a background processing run.

    Status flow:
      queued → preprocessing → ocr → analyzing → completed
                                                ↘ failed
    """

    __tablename__ = "processing_jobs"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    game_id: Mapped[str] = mapped_column(
        String(50), ForeignKey("games.id", ondelete="CASCADE"), nullable=False, unique=True
    )

    # JobStatus: queued / preprocessing / ocr / analyzing / completed / failed
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="queued")

    # Populated once Celery picks up the task (Phase 4+)
    celery_task_id: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)

    # Human-readable error for the failed state
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now
    )
    started_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    game: Mapped[Game] = relationship(back_populates="processing_job")

    def __repr__(self) -> str:
        return f"<ProcessingJob id={self.id!r} status={self.status!r}>"


# ── MoveEntry ─────────────────────────────────────────────────────────────────


class MoveEntry(Base):
    """One validated ply (half-move) in an analyzed game."""

    __tablename__ = "move_entries"
    __table_args__ = (
        UniqueConstraint("game_id", "ply_index", name="uq_move_game_ply"),
    )

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    game_id: Mapped[str] = mapped_column(
        String(50), ForeignKey("games.id", ondelete="CASCADE"), nullable=False, index=True
    )

    ply_index: Mapped[int] = mapped_column(Integer, nullable=False)
    color: Mapped[str] = mapped_column(String(5), nullable=False)  # "white" | "black"
    move_number: Mapped[int] = mapped_column(Integer, nullable=False)

    selected_san: Mapped[Optional[str]] = mapped_column(String(20), nullable=True)
    selected_uci: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
    fen_before: Mapped[str] = mapped_column(Text, nullable=False)
    fen_after: Mapped[str] = mapped_column(Text, nullable=False)

    is_legal: Mapped[bool] = mapped_column(Boolean, nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)
    needs_review: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    # Comma-separated FIDE alert codes for this ply
    fide_alerts_csv: Mapped[str] = mapped_column(String(255), nullable=False, default="")

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now
    )

    game: Mapped[Game] = relationship(back_populates="move_entries")
    crop: Mapped[Optional[MoveCrop]] = relationship(
        back_populates="move_entry", uselist=False, cascade="all, delete-orphan"
    )
    ocr_result: Mapped[Optional[OCRResult]] = relationship(
        back_populates="move_entry", uselist=False, cascade="all, delete-orphan"
    )
    review_actions: Mapped[List[ReviewAction]] = relationship(
        back_populates="move_entry",
        order_by="ReviewAction.corrected_at",
        cascade="all, delete-orphan",
    )

    def __repr__(self) -> str:
        return f"<MoveEntry ply={self.ply_index} san={self.selected_san!r}>"


# ── MoveCrop ──────────────────────────────────────────────────────────────────


class MoveCrop(Base):
    """Path to the cropped handwritten cell image for one move (Phase 3+)."""

    __tablename__ = "move_crops"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    move_entry_id: Mapped[str] = mapped_column(
        String(50),
        ForeignKey("move_entries.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    crop_image_path: Mapped[str] = mapped_column(String(512), nullable=False)

    # Bounding box in the original (pre-crop) image coordinates — optional
    # so that rows created before Phase 3 are not broken.
    bbox_x: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    bbox_y: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    bbox_w: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    bbox_h: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    move_entry: Mapped[MoveEntry] = relationship(back_populates="crop")


# ── OCRResult ─────────────────────────────────────────────────────────────────


class OCRResult(Base):
    """Raw OCR output for one move cell (Phase 4+)."""

    __tablename__ = "ocr_results"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    move_entry_id: Mapped[str] = mapped_column(
        String(50),
        ForeignKey("move_entries.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )

    raw_text: Mapped[str] = mapped_column(String(50), nullable=False)
    # JSON: list of {"text": str, "confidence": float}
    candidates_json: Mapped[dict] = mapped_column(JSON, nullable=False)
    normalized_text: Mapped[str] = mapped_column(String(50), nullable=False)

    move_entry: Mapped[MoveEntry] = relationship(back_populates="ocr_result")


# ── RuleFindingDB ─────────────────────────────────────────────────────────────


class RuleFindingDB(Base):
    """Persisted FIDE / game-state finding for a game."""

    __tablename__ = "rule_findings"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    game_id: Mapped[str] = mapped_column(
        String(50), ForeignKey("games.id", ondelete="CASCADE"), nullable=False, index=True
    )

    ply_index: Mapped[int] = mapped_column(Integer, nullable=False)
    # FindingType enum value (string)
    type: Mapped[str] = mapped_column(String(40), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    is_automatic: Mapped[bool] = mapped_column(Boolean, nullable=False)

    game: Mapped[Game] = relationship(back_populates="rule_findings")


# ── ReviewAction ──────────────────────────────────────────────────────────────


class ReviewAction(Base):
    """Records a manual correction made by the arbiter (Phase 6+)."""

    __tablename__ = "review_actions"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    move_entry_id: Mapped[str] = mapped_column(
        String(50),
        ForeignKey("move_entries.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    original_san: Mapped[str] = mapped_column(String(20), nullable=False)
    corrected_san: Mapped[str] = mapped_column(String(20), nullable=False)
    corrected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now
    )

    move_entry: Mapped[MoveEntry] = relationship(back_populates="review_actions")


# ── ExportArtifact ────────────────────────────────────────────────────────────


class ExportArtifact(Base):
    """A generated export file (PGN, PDF, etc.) for a game."""

    __tablename__ = "export_artifacts"

    id: Mapped[str] = mapped_column(String(50), primary_key=True, default=_uuid)
    game_id: Mapped[str] = mapped_column(
        String(50), ForeignKey("games.id", ondelete="CASCADE"), nullable=False, index=True
    )

    format: Mapped[str] = mapped_column(String(10), nullable=False)   # "pgn", "pdf"
    file_path: Mapped[str] = mapped_column(String(512), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_now
    )

    game: Mapped[Game] = relationship(back_populates="export_artifacts")
