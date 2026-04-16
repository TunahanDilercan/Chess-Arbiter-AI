"""
Phase 7: Server-Sent Events (SSE) for job status streaming.

GET /api/sse/{job_id}

Streams real-time status updates for a processing job using Redis pub/sub.
The Celery worker publishes a JSON message to the channel ``job:{job_id}:status``
after every status transition.  This endpoint subscribes, forwards each message
as an SSE event, and closes the stream on terminal statuses or timeout.

SSE event format (each line is followed by a blank line)::

    data: {"job_id": "...", "status": "...", "error_message": null}\n\n

Guarantees:
  - The Redis subscription is always released in a ``finally`` block.
  - The stream closes immediately on ``completed`` or ``failed`` status.
  - The stream closes after SSE_TIMEOUT_SECONDS (default 600 s = 10 min).
  - Client disconnects are detected via the asyncio CancelledError / disconnect.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import AsyncGenerator, Optional

import redis.asyncio as aioredis
from fastapi import APIRouter, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy import select

from config import settings
from database import AsyncSessionLocal
from models.game import ProcessingJob

logger = logging.getLogger(__name__)

router = APIRouter()

# Maximum seconds to keep the stream open (hard timeout).
SSE_TIMEOUT_SECONDS: int = 600

# How long to block waiting for a pub/sub message per iteration (seconds).
_POLL_TIMEOUT: float = 1.0

# Statuses that signal the pipeline is done — stream must close after these.
_TERMINAL_STATUSES: frozenset[str] = frozenset({"completed", "failed"})


# ── Helpers ───────────────────────────────────────────────────────────────────


def _sse_event(job_id: str, status_str: str, error_message: Optional[str] = None) -> str:
    """Format a single SSE data line."""
    payload = json.dumps({
        "job_id": job_id,
        "status": status_str,
        "error_message": error_message,
    })
    return f"data: {payload}\n\n"


async def _current_status(job_id: str) -> Optional[tuple[str, Optional[str]]]:
    """
    Look up the current job status from PostgreSQL.

    Returns (status, error_message) or None when the job is not found.
    Used to immediately emit the current state before subscribing to pub/sub,
    so late-connecting clients still get an up-to-date snapshot.
    """
    async with AsyncSessionLocal() as db:
        stmt = select(ProcessingJob).where(ProcessingJob.id == job_id)
        result = await db.execute(stmt)
        job = result.scalar_one_or_none()
        if job is None:
            return None
        return job.status, job.error_message


# ── Event generator ───────────────────────────────────────────────────────────


async def _event_generator(
    job_id: str,
    initial_status: str,
    initial_error: Optional[str],
) -> AsyncGenerator[str, None]:
    """
    Async generator that yields SSE-formatted strings.

    1. Immediately emits the current DB status (already fetched by the route).
    2. If that status is terminal, closes immediately.
    3. Otherwise subscribes to ``job:{job_id}:status`` on Redis and forwards
       every published message until a terminal status arrives or timeout.
    """
    # Step 1: emit snapshot immediately so client sees current state without delay.
    yield _sse_event(job_id, initial_status, initial_error)

    if initial_status in _TERMINAL_STATUSES:
        return

    channel = f"job:{job_id}:status"
    client: Optional[aioredis.Redis] = None
    pubsub: Optional[aioredis.client.PubSub] = None

    try:
        client = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        pubsub = client.pubsub()
        await pubsub.subscribe(channel)
        logger.debug("SSE subscribed to channel %s", channel)

        deadline = asyncio.get_event_loop().time() + SSE_TIMEOUT_SECONDS

        while True:
            remaining = deadline - asyncio.get_event_loop().time()
            if remaining <= 0:
                logger.info("SSE timeout for job_id=%s", job_id)
                # Emit a synthetic timeout event so the client knows why it closed.
                yield _sse_event(job_id, "timeout")
                return

            # Block for up to _POLL_TIMEOUT seconds waiting for a message.
            wait = min(_POLL_TIMEOUT, remaining)
            try:
                message = await asyncio.wait_for(
                    pubsub.get_message(ignore_subscribe_messages=True, timeout=0),
                    timeout=wait,
                )
            except asyncio.TimeoutError:
                continue

            if message is None:
                await asyncio.sleep(0)  # yield to event loop
                continue

            if message["type"] != "message":
                continue

            try:
                payload = json.loads(message["data"])
                job_status: str = payload["status"]
                error_msg: Optional[str] = payload.get("error_message")
            except (json.JSONDecodeError, KeyError) as exc:
                logger.warning("Malformed SSE message on %s: %s — %s", channel, message["data"], exc)
                continue

            yield _sse_event(job_id, job_status, error_msg)

            if job_status in _TERMINAL_STATUSES:
                logger.debug("Terminal status %r — closing SSE for job %s", job_status, job_id)
                return

    except asyncio.CancelledError:
        # Client disconnected.
        logger.debug("SSE client disconnected for job_id=%s", job_id)
        raise
    finally:
        if pubsub is not None:
            try:
                await pubsub.unsubscribe(channel)
                await pubsub.aclose()
            except Exception:  # noqa: BLE001
                pass
        if client is not None:
            try:
                await client.aclose()
            except Exception:  # noqa: BLE001
                pass
        logger.debug("SSE Redis connection released for job_id=%s", job_id)


# ── Endpoint ──────────────────────────────────────────────────────────────────


@router.get(
    "/{job_id}",
    summary="Stream job status updates via SSE (Phase 7)",
    description=(
        "Open a Server-Sent Events stream for a processing job.\n\n"
        "Each event has the format:\n"
        "```\ndata: {\"job_id\": \"...\", \"status\": \"...\", \"error_message\": null}\\n\\n\n```\n\n"
        "The stream closes automatically when `status` is `completed` or `failed`, "
        "or after a 10-minute timeout."
    ),
    responses={
        200: {"description": "SSE stream (text/event-stream)."},
        404: {"description": "Job not found."},
    },
)
async def stream_job_status(job_id: str) -> StreamingResponse:
    # Look up the current DB state before subscribing to avoid a race where
    # the job finished before the client connected.
    db_state = await _current_status(job_id)
    if db_state is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Job '{job_id}' not found.",
        )

    initial_status, initial_error = db_state

    return StreamingResponse(
        _event_generator(job_id, initial_status, initial_error),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",  # disable nginx buffering
        },
    )
