"""
Structured JSON logging configuration for Arbiter AI.

Usage:
    from logging_config import setup_logging
    setup_logging(debug=settings.DEBUG)

All log records are emitted as single-line JSON objects to stdout, which is
the expected format for production log aggregators (Datadog, CloudWatch, etc.).
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone
from typing import Any


class _JSONFormatter(logging.Formatter):
    """Format log records as single-line JSON objects."""

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            entry["exc_info"] = self.formatException(record.exc_info)
        if record.stack_info:
            entry["stack_info"] = self.formatStack(record.stack_info)
        # Forward any extra fields attached to the log record.
        for key, value in record.__dict__.items():
            if key not in (
                "name", "msg", "args", "levelname", "levelno", "pathname",
                "filename", "module", "exc_info", "exc_text", "stack_info",
                "lineno", "funcName", "created", "msecs", "relativeCreated",
                "thread", "threadName", "processName", "process", "message",
                "taskName",
            ):
                entry[key] = value
        return json.dumps(entry, default=str)


def setup_logging(debug: bool = False) -> None:
    """
    Configure root logger with structured JSON output.

    Call once at application startup, before any other imports that
    might call logging.getLogger().
    """
    level = logging.DEBUG if debug else logging.INFO

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(_JSONFormatter())

    logging.basicConfig(level=level, handlers=[handler], force=True)

    # Silence overly verbose third-party loggers in production.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("sqlalchemy.engine").setLevel(
        logging.INFO if debug else logging.WARNING
    )
    logging.getLogger("transformers").setLevel(logging.WARNING)
    logging.getLogger("torch").setLevel(logging.WARNING)
