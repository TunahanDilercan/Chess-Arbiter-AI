"""Complete the crop schema and preserve review provenance."""
from alembic import op
import sqlalchemy as sa

revision = "b2c3d4e5f6a7"
down_revision = "a1b2c3d4e5f6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Development databases may already have crop columns from create_all.
    inspector = None if op.get_context().as_sql else sa.inspect(op.get_bind())
    additions = {
        "move_crops": [(name, sa.Integer()) for name in ("bbox_x", "bbox_y", "bbox_w", "bbox_h")],
        "move_entries": [("review_reasons_json", sa.JSON())],
        "ocr_results": [("notation_locale", sa.String(10))],
    }
    for table, columns in additions.items():
        existing = {column["name"] for column in inspector.get_columns(table)} if inspector else set()
        for name, data_type in columns:
            if name not in existing:
                op.add_column(table, sa.Column(name, data_type, nullable=True))
    with op.batch_alter_table("games") as batch:
        batch.alter_column("session_id", existing_type=sa.String(36), type_=sa.String(64), existing_nullable=False)


def downgrade() -> None:
    if op.get_context().as_sql:
        raise RuntimeError("Downgrade requires an online session-length safety check.")
    count = op.get_bind().execute(sa.text(
        "SELECT COUNT(*) FROM games WHERE length(session_id) > 36"
    )).scalar_one()
    if count:
        raise RuntimeError("Cannot downgrade: session identifiers exceed 36 characters.")
    with op.batch_alter_table("games") as batch:
        batch.alter_column("session_id", existing_type=sa.String(64), type_=sa.String(36), existing_nullable=False)
    op.drop_column("ocr_results", "notation_locale")
    op.drop_column("move_entries", "review_reasons_json")
    for name in ("bbox_x", "bbox_y", "bbox_w", "bbox_h"):
        op.drop_column("move_crops", name)
