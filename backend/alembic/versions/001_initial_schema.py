"""Initial schema — all Phase 2 tables.

Revision ID: a1b2c3d4e5f6
Revises: (none)
Create Date: 2024-01-01 00:00:00.000000

Tables created:
  games, uploaded_assets, processing_jobs, move_entries,
  move_crops, ocr_results, rule_findings, review_actions, export_artifacts
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── games ─────────────────────────────────────────────────────────────────
    op.create_table(
        "games",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("session_id", sa.String(36), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("pgn", sa.Text, nullable=True),
        sa.Column("failure_point_ply", sa.Integer, nullable=True),
        sa.Column("locale", sa.String(10), nullable=False, server_default="en"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
    )
    op.create_index("ix_games_session_id", "games", ["session_id"])

    # ── uploaded_assets ───────────────────────────────────────────────────────
    op.create_table(
        "uploaded_assets",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("game_id", sa.String(36), sa.ForeignKey("games.id", ondelete="CASCADE"), nullable=False),
        sa.Column("file_path", sa.String(512), nullable=False),
        sa.Column("file_type", sa.String(64), nullable=False),
        sa.Column("original_filename", sa.String(255), nullable=True),
        sa.Column("file_size_bytes", sa.Integer, nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
    )
    op.create_index("ix_uploaded_assets_game_id", "uploaded_assets", ["game_id"])

    # ── processing_jobs ───────────────────────────────────────────────────────
    op.create_table(
        "processing_jobs",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("game_id", sa.String(36), sa.ForeignKey("games.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("celery_task_id", sa.String(255), nullable=True),
        sa.Column("error_message", sa.Text, nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )

    # ── move_entries ──────────────────────────────────────────────────────────
    op.create_table(
        "move_entries",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("game_id", sa.String(36), sa.ForeignKey("games.id", ondelete="CASCADE"), nullable=False),
        sa.Column("ply_index", sa.Integer, nullable=False),
        sa.Column("color", sa.String(5), nullable=False),
        sa.Column("move_number", sa.Integer, nullable=False),
        sa.Column("selected_san", sa.String(20), nullable=True),
        sa.Column("selected_uci", sa.String(10), nullable=True),
        sa.Column("fen_before", sa.Text, nullable=False),
        sa.Column("fen_after", sa.Text, nullable=False),
        sa.Column("is_legal", sa.Boolean, nullable=False),
        sa.Column("confidence", sa.Float, nullable=False, server_default="1.0"),
        sa.Column("needs_review", sa.Boolean, nullable=False, server_default="false"),
        sa.Column("fide_alerts_csv", sa.String(255), nullable=False, server_default=""),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.UniqueConstraint("game_id", "ply_index", name="uq_move_game_ply"),
    )
    op.create_index("ix_move_entries_game_id", "move_entries", ["game_id"])

    # ── move_crops ────────────────────────────────────────────────────────────
    op.create_table(
        "move_crops",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("move_entry_id", sa.String(36), sa.ForeignKey("move_entries.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("crop_image_path", sa.String(512), nullable=False),
    )

    # ── ocr_results ──��────────────────────────────────────────────────────────
    op.create_table(
        "ocr_results",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("move_entry_id", sa.String(36), sa.ForeignKey("move_entries.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("raw_text", sa.String(50), nullable=False),
        sa.Column("candidates_json", sa.JSON, nullable=False),
        sa.Column("normalized_text", sa.String(50), nullable=False),
    )

    # ── rule_findings ─────────────────────────────────────────────────────────
    op.create_table(
        "rule_findings",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("game_id", sa.String(36), sa.ForeignKey("games.id", ondelete="CASCADE"), nullable=False),
        sa.Column("ply_index", sa.Integer, nullable=False),
        sa.Column("type", sa.String(40), nullable=False),
        sa.Column("description", sa.Text, nullable=False),
        sa.Column("is_automatic", sa.Boolean, nullable=False),
    )
    op.create_index("ix_rule_findings_game_id", "rule_findings", ["game_id"])

    # ── review_actions ────────────────────────────────────────────────────────
    op.create_table(
        "review_actions",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("move_entry_id", sa.String(36), sa.ForeignKey("move_entries.id", ondelete="CASCADE"), nullable=False),
        sa.Column("original_san", sa.String(20), nullable=False),
        sa.Column("corrected_san", sa.String(20), nullable=False),
        sa.Column(
            "corrected_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
    )
    op.create_index("ix_review_actions_move_entry_id", "review_actions", ["move_entry_id"])

    # ── export_artifacts ──────────────────────────────────────────────────────
    op.create_table(
        "export_artifacts",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("game_id", sa.String(36), sa.ForeignKey("games.id", ondelete="CASCADE"), nullable=False),
        sa.Column("format", sa.String(10), nullable=False),
        sa.Column("file_path", sa.String(512), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
    )
    op.create_index("ix_export_artifacts_game_id", "export_artifacts", ["game_id"])


def downgrade() -> None:
    op.drop_table("export_artifacts")
    op.drop_table("review_actions")
    op.drop_table("rule_findings")
    op.drop_table("ocr_results")
    op.drop_table("move_crops")
    op.drop_table("move_entries")
    op.drop_table("processing_jobs")
    op.drop_table("uploaded_assets")
    op.drop_table("games")
