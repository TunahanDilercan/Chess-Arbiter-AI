"""
Phase 7: Tests for SSE job status streaming.

GET /api/sse/{job_id}

Test categories:
  - TestSSE404         — unknown job returns 404
  - TestSSETerminal    — already-completed / already-failed jobs emit one event
  - TestSSEStreaming   — in-progress jobs stream events until terminal status
  - TestSSEFormat      — event JSON keys, content-type header
  - TestSSECleanup     — Redis sub/client always released after stream closes

Run: pytest tests/test_sse.py -v
"""

from __future__ import annotations

import asyncio
import json
from typing import AsyncGenerator, List, Optional
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from main import app


# ── Fake Redis helpers ────────────────────────────────────────────────────────


class FakePubSub:
    """
    Pub/sub stub that returns pre-loaded messages in order, then None.

    After all messages are consumed ``get_message`` returns ``None`` on each
    call so the generator's polling loop continues until a terminal status
    closes the stream.
    """

    def __init__(self, messages: List[dict]) -> None:
        self._messages = list(messages)
        self._idx = 0
        self.unsubscribe = AsyncMock()
        self.aclose = AsyncMock()

    async def subscribe(self, channel: str) -> None:
        pass

    async def get_message(
        self,
        ignore_subscribe_messages: bool = True,
        timeout: float = 0,
    ) -> Optional[dict]:
        if self._idx < len(self._messages):
            msg = self._messages[self._idx]
            self._idx += 1
            return msg
        await asyncio.sleep(0)  # yield to event loop; signal "no message yet"
        return None


class FakeRedis:
    def __init__(self, fake_pubsub: FakePubSub) -> None:
        self._pubsub = fake_pubsub
        self.aclose = AsyncMock()

    def pubsub(self) -> FakePubSub:
        return self._pubsub


def _msg(job_id: str, status: str, error: Optional[str] = None) -> dict:
    """Build a fake Redis pub/sub message for a status update."""
    payload = json.dumps({"job_id": job_id, "status": status, "error_message": error})
    return {"type": "message", "data": payload}


# ── Fixtures ──────────────────────────────────────────────────────────────────


@pytest_asyncio.fixture
async def plain_client() -> AsyncGenerator[AsyncClient, None]:
    """
    httpx client with no DB override.

    All tests in this module mock ``_current_status`` directly so no real
    DB connection is needed.
    """
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


# ── Collection helper ─────────────────────────────────────────────────────────


async def _collect_events(
    client: AsyncClient,
    url: str,
    *,
    limit: int = 30,
) -> List[dict]:
    """
    Open an SSE stream and collect all ``data:`` events.

    Breaks after *limit* events as a safety net so tests never hang.
    """
    events: List[dict] = []
    async with client.stream("GET", url) as resp:
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}"
        async for line in resp.aiter_lines():
            if line.startswith("data:"):
                events.append(json.loads(line[5:].strip()))
            if len(events) >= limit:
                break
    return events


# ── TestSSE404 ────────────────────────────────────────────────────────────────


class TestSSE404:
    @pytest.mark.asyncio
    async def test_unknown_job_returns_404(self, plain_client: AsyncClient) -> None:
        with patch("api.routes.sse._current_status", AsyncMock(return_value=None)):
            resp = await plain_client.get("/api/sse/nonexistent-job")
        assert resp.status_code == 404

    @pytest.mark.asyncio
    async def test_404_body_mentions_job_id(self, plain_client: AsyncClient) -> None:
        job_id = "missing-job-123"
        with patch("api.routes.sse._current_status", AsyncMock(return_value=None)):
            resp = await plain_client.get(f"/api/sse/{job_id}")
        assert job_id in resp.text


# ── TestSSETerminal ───────────────────────────────────────────────────────────


class TestSSETerminal:
    """Jobs already in a terminal state must emit exactly one event and close."""

    @pytest.mark.asyncio
    async def test_completed_job_emits_one_event(self, plain_client: AsyncClient) -> None:
        job_id = "job-done"
        with patch("api.routes.sse._current_status", AsyncMock(return_value=("completed", None))):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}")

        assert len(events) == 1
        assert events[0]["status"] == "completed"
        assert events[0]["job_id"] == job_id

    @pytest.mark.asyncio
    async def test_failed_job_emits_error_message(self, plain_client: AsyncClient) -> None:
        job_id = "job-failed"
        err = "Grid detection failed: contours not found"
        with patch("api.routes.sse._current_status", AsyncMock(return_value=("failed", err))):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}")

        assert len(events) == 1
        assert events[0]["status"] == "failed"
        assert events[0]["error_message"] == err

    @pytest.mark.asyncio
    async def test_completed_job_does_not_open_redis(self, plain_client: AsyncClient) -> None:
        """No Redis connection should be opened for already-terminal jobs."""
        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("completed", None))),
            patch("api.routes.sse.aioredis.from_url") as mock_from_url,
        ):
            await _collect_events(plain_client, "/api/sse/done-job")

        mock_from_url.assert_not_called()


# ── TestSSEStreaming ──────────────────────────────────────────────────────────


class TestSSEStreaming:
    """In-progress jobs stream events from Redis until a terminal status."""

    @pytest.mark.asyncio
    async def test_initial_db_snapshot_emitted_first(self, plain_client: AsyncClient) -> None:
        """The current DB status must be the very first event — before any pub/sub."""
        job_id = "job-snap"
        pubsub = FakePubSub([_msg(job_id, "completed")])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("preprocessing", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}")

        assert events[0]["status"] == "preprocessing"

    @pytest.mark.asyncio
    async def test_stream_delivers_intermediate_status(self, plain_client: AsyncClient) -> None:
        job_id = "job-intermediate"
        pubsub = FakePubSub([
            _msg(job_id, "ocr_processing"),
            _msg(job_id, "completed"),
        ])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("queued", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}")

        statuses = [e["status"] for e in events]
        assert "ocr_processing" in statuses

    @pytest.mark.asyncio
    async def test_stream_closes_after_completed(self, plain_client: AsyncClient) -> None:
        """Events after 'completed' must not be emitted."""
        job_id = "job-post-complete"
        pubsub = FakePubSub([
            _msg(job_id, "completed"),
            _msg(job_id, "ghost_status"),  # must never arrive
        ])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("queued", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}")

        statuses = [e["status"] for e in events]
        assert "ghost_status" not in statuses
        assert statuses[-1] == "completed"

    @pytest.mark.asyncio
    async def test_stream_closes_after_failed(self, plain_client: AsyncClient) -> None:
        job_id = "job-fail-close"
        pubsub = FakePubSub([
            _msg(job_id, "failed", "Unexpected error"),
            _msg(job_id, "ghost_status"),
        ])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("cropping", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}")

        statuses = [e["status"] for e in events]
        assert "ghost_status" not in statuses
        assert statuses[-1] == "failed"

    @pytest.mark.asyncio
    async def test_full_pipeline_sequence(self, plain_client: AsyncClient) -> None:
        """All pipeline stages arrive and stream terminates on completed."""
        job_id = "job-pipeline"
        pipeline_statuses = [
            "preprocessing", "cropping",
            "ocr_processing", "ocr_complete",
            "analyzing", "completed",
        ]
        pubsub = FakePubSub([_msg(job_id, s) for s in pipeline_statuses])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("queued", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}", limit=50)

        statuses = [e["status"] for e in events]
        assert statuses[0] == "queued"
        for s in pipeline_statuses:
            assert s in statuses, f"Expected status {s!r} in stream"
        assert statuses[-1] == "completed"

    @pytest.mark.asyncio
    async def test_non_message_type_events_ignored(self, plain_client: AsyncClient) -> None:
        """Pub/sub messages with type != 'message' (e.g. subscribe ack) are skipped."""
        job_id = "job-non-msg"
        pubsub = FakePubSub([
            {"type": "subscribe", "data": 1},     # subscribe ack — must be ignored
            _msg(job_id, "completed"),
        ])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("queued", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            events = await _collect_events(plain_client, f"/api/sse/{job_id}")

        # Only the DB snapshot and the "completed" event should be present.
        statuses = [e["status"] for e in events]
        assert "completed" in statuses
        # No event should have status == 1 (from the subscribe ack data)
        for e in events:
            assert isinstance(e["status"], str)


# ── TestSSEFormat ─────────────────────────────────────────────────────────────


class TestSSEFormat:
    @pytest.mark.asyncio
    async def test_event_has_required_keys(self, plain_client: AsyncClient) -> None:
        with patch("api.routes.sse._current_status", AsyncMock(return_value=("completed", None))):
            events = await _collect_events(plain_client, "/api/sse/fmt-job")

        ev = events[0]
        assert "job_id" in ev
        assert "status" in ev
        assert "error_message" in ev

    @pytest.mark.asyncio
    async def test_error_message_null_when_no_error(self, plain_client: AsyncClient) -> None:
        with patch("api.routes.sse._current_status", AsyncMock(return_value=("completed", None))):
            events = await _collect_events(plain_client, "/api/sse/null-err-job")

        assert events[0]["error_message"] is None

    @pytest.mark.asyncio
    async def test_content_type_is_event_stream(self, plain_client: AsyncClient) -> None:
        with patch("api.routes.sse._current_status", AsyncMock(return_value=("completed", None))):
            async with plain_client.stream("GET", "/api/sse/ctype-job") as resp:
                content_type = resp.headers.get("content-type", "")
        assert "text/event-stream" in content_type

    @pytest.mark.asyncio
    async def test_cache_control_no_cache(self, plain_client: AsyncClient) -> None:
        with patch("api.routes.sse._current_status", AsyncMock(return_value=("completed", None))):
            async with plain_client.stream("GET", "/api/sse/cc-job") as resp:
                cache_control = resp.headers.get("cache-control", "")
        assert "no-cache" in cache_control


# ── TestSSECleanup ────────────────────────────────────────────────────────────


class TestSSECleanup:
    """Redis pub/sub resources must always be released."""

    @pytest.mark.asyncio
    async def test_pubsub_unsubscribed_after_completed(self, plain_client: AsyncClient) -> None:
        job_id = "job-unsub"
        pubsub = FakePubSub([_msg(job_id, "completed")])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("queued", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            await _collect_events(plain_client, f"/api/sse/{job_id}")

        pubsub.unsubscribe.assert_called_once()

    @pytest.mark.asyncio
    async def test_pubsub_aclose_called(self, plain_client: AsyncClient) -> None:
        job_id = "job-aclose"
        pubsub = FakePubSub([_msg(job_id, "completed")])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("queued", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            await _collect_events(plain_client, f"/api/sse/{job_id}")

        pubsub.aclose.assert_called_once()

    @pytest.mark.asyncio
    async def test_redis_client_aclose_called(self, plain_client: AsyncClient) -> None:
        job_id = "job-redis-close"
        pubsub = FakePubSub([_msg(job_id, "completed")])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("queued", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            await _collect_events(plain_client, f"/api/sse/{job_id}")

        redis.aclose.assert_called_once()

    @pytest.mark.asyncio
    async def test_cleanup_on_failed_status(self, plain_client: AsyncClient) -> None:
        """Cleanup must run even when the job fails."""
        job_id = "job-fail-cleanup"
        pubsub = FakePubSub([_msg(job_id, "failed", "boom")])
        redis = FakeRedis(pubsub)

        with (
            patch("api.routes.sse._current_status", AsyncMock(return_value=("cropping", None))),
            patch("api.routes.sse.aioredis.from_url", return_value=redis),
        ):
            await _collect_events(plain_client, f"/api/sse/{job_id}")

        pubsub.unsubscribe.assert_called_once()
        pubsub.aclose.assert_called_once()
        redis.aclose.assert_called_once()
