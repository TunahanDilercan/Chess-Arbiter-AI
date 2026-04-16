"""
Celery application instance for Arbiter AI background workers.

All background processing tasks are routed through this app.
The broker and backend both use Redis (configured via REDIS_URL in config.py).

Usage:
    # Start a worker (from the backend/ directory):
    celery -A workers.celery_app worker --loglevel=info

    # Start a worker with concurrency 2:
    celery -A workers.celery_app worker --concurrency=2 --loglevel=info
"""

from celery import Celery

from config import settings

celery_app = Celery(
    "arbiter",
    broker=settings.REDIS_URL,
    backend=settings.REDIS_URL,
    include=["workers.processing_tasks"],
)

celery_app.conf.update(
    # Serialisation
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    # Timezone
    timezone="UTC",
    enable_utc=True,
    # Retry behaviour for transient failures
    task_acks_late=True,           # ack only after the task succeeds/fails
    task_reject_on_worker_lost=True,
    # Results expire after 24 hours — we persist outcomes in PostgreSQL
    result_expires=86400,
    # Route all tasks to the default queue
    task_default_queue="arbiter",
    task_routes={
        "workers.processing_tasks.process_scoresheet_task": {"queue": "arbiter"},
    },
)
