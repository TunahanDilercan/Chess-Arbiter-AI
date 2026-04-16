"""
Storage service — abstract backend for file persistence.

Two implementations:
  LocalStorageBackend  — writes to the local filesystem (dev / Docker)
  S3StorageBackend     — writes to AWS S3 / Cloudflare R2 (production)

Usage:
    storage = get_storage()
    key = f"uploads/{game_id}/{filename}"
    path = await storage.save(file_bytes, key, content_type="image/jpeg")
    url  = await storage.get_url(key)

The active backend is selected by settings.STORAGE_BACKEND ("local" | "s3").
"""

from __future__ import annotations

import asyncio
import logging
from abc import ABC, abstractmethod
from pathlib import Path

from config import settings

logger = logging.getLogger(__name__)


# ── Abstract interface ────────────────────────────────────────────────────────


class StorageBackend(ABC):
    """
    Abstract storage backend.  All methods are async so callers are uniform
    regardless of whether the backend is local I/O or a remote API call.
    """

    @abstractmethod
    async def save(self, data: bytes, key: str, content_type: str) -> str:
        """
        Persist data at the given storage key.

        Args:
            data:         Raw file bytes.
            key:          Storage key / relative path (e.g. "uploads/game-id/file.jpg").
            content_type: MIME type of the file.

        Returns:
            The storage path or S3 key as stored — use get_url() to get a servable URL.
        """

    @abstractmethod
    async def get_url(self, key: str) -> str:
        """
        Return a URL suitable for serving or linking to the file.

        For local storage this is a relative URL path.
        For S3 this is a time-limited presigned URL.
        """

    @abstractmethod
    async def load(self, key: str) -> bytes:
        """
        Return the raw bytes stored at *key*.

        Raises:
            FileNotFoundError: If the key does not exist in storage.
        """

    @abstractmethod
    async def delete(self, key: str) -> None:
        """Delete the file at the given key.  No-op if not found."""


# ── Local filesystem backend ──────────────────────────────────────────────────


class LocalStorageBackend(StorageBackend):
    """
    Writes files to the local filesystem under base_path.

    Directory structure mirrors the key:
      base_path/uploads/{game_id}/original.jpg
      base_path/crops/{game_id}/{ply_index}.png

    In Docker the base_path is mounted as a volume so files survive container restarts.
    """

    def __init__(self, base_path: str) -> None:
        self.base_path = Path(base_path).resolve()
        self.base_path.mkdir(parents=True, exist_ok=True)

    async def save(self, data: bytes, key: str, content_type: str) -> str:
        dest = self.base_path / key
        dest.parent.mkdir(parents=True, exist_ok=True)

        # Run blocking I/O in the default thread pool so the event loop is not blocked
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, dest.write_bytes, data)

        logger.debug("LocalStorage: saved %d bytes → %s", len(data), dest)
        return key  # return relative key, not absolute path

    async def load(self, key: str) -> bytes:
        dest = self.base_path / key
        if not dest.exists():
            raise FileNotFoundError(f"LocalStorage: key not found: {key}")
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, dest.read_bytes)

    async def get_url(self, key: str) -> str:
        # Served via FastAPI StaticFiles mount at /storage (registered in main.py)
        return f"/storage/{key}"

    async def delete(self, key: str) -> None:
        dest = self.base_path / key
        if dest.exists():
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(None, dest.unlink)
            logger.debug("LocalStorage: deleted %s", dest)


# ── S3 backend (production) ───────────────────────────────────────────────────


class S3StorageBackend(StorageBackend):
    """
    Stores files in AWS S3 or any S3-compatible service (Cloudflare R2, MinIO).

    Requires boto3 (listed in requirements.txt Phase 2+ section).
    All boto3 calls run in a thread executor — boto3 is synchronous.

    Presigned URLs expire after 1 hour by default.
    """

    def __init__(self, bucket: str, region: str, presign_expiry: int = 3600) -> None:
        try:
            import boto3  # noqa: PLC0415
            self._s3 = boto3.client("s3", region_name=region)
        except ImportError as exc:
            raise RuntimeError(
                "boto3 is required for S3 storage. "
                "Uncomment boto3 in requirements.txt and reinstall."
            ) from exc

        self.bucket = bucket
        self.region = region
        self.presign_expiry = presign_expiry

    async def save(self, data: bytes, key: str, content_type: str) -> str:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(
            None,
            lambda: self._s3.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=data,
                ContentType=content_type,
            ),
        )
        logger.debug("S3Storage: uploaded %d bytes → s3://%s/%s", len(data), self.bucket, key)
        return key

    async def load(self, key: str) -> bytes:
        loop = asyncio.get_running_loop()
        response = await loop.run_in_executor(
            None,
            lambda: self._s3.get_object(Bucket=self.bucket, Key=key),
        )
        return response["Body"].read()

    async def get_url(self, key: str) -> str:
        loop = asyncio.get_running_loop()
        url: str = await loop.run_in_executor(
            None,
            lambda: self._s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": self.bucket, "Key": key},
                ExpiresIn=self.presign_expiry,
            ),
        )
        return url

    async def delete(self, key: str) -> None:
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(
            None,
            lambda: self._s3.delete_object(Bucket=self.bucket, Key=key),
        )


# ── Factory ───────────────────────────────────────────────────────────────────


def get_storage() -> StorageBackend:
    """
    FastAPI dependency / factory that returns the configured storage backend.

    Reads settings.STORAGE_BACKEND ("local" | "s3").
    """
    if settings.STORAGE_BACKEND == "s3":
        return S3StorageBackend(
            bucket=settings.S3_BUCKET,
            region=settings.S3_REGION,
        )
    return LocalStorageBackend(base_path=settings.LOCAL_STORAGE_PATH)


# Module-level singleton used by routes via Depends(get_storage)
_storage_instance: StorageBackend | None = None


def get_storage_cached() -> StorageBackend:
    """Cached singleton version — avoids re-instantiating on every request."""
    global _storage_instance
    if _storage_instance is None:
        _storage_instance = get_storage()
    return _storage_instance
