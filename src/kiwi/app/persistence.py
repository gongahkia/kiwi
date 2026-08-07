"""Recoverable non-authoritative file writes at application IO boundaries."""

from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path


class RecoverableWriteFailureCode(StrEnum):
    """Stable failures while atomically replacing local application data."""

    CREATE_DIRECTORY = "PW001_CREATE_DIRECTORY"
    WRITE_TEMPORARY = "PW002_WRITE_TEMPORARY"
    ROTATE_BACKUP = "PW003_ROTATE_BACKUP"
    REPLACE_PRIMARY = "PW004_REPLACE_PRIMARY"


@dataclass(frozen=True, slots=True)
class RecoverableWriteFailure:
    """A concise local-write failure that does not expose a Python traceback."""

    code: RecoverableWriteFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, RecoverableWriteFailureCode):
            raise TypeError("recoverable write failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("recoverable write failure requires a message")


type RecoverableWriteResult = RecoverableWriteFailure | None


def backup_path(path: Path) -> Path:
    """Return the adjacent last-known-good path for one local durable file."""
    if not isinstance(path, Path):
        raise TypeError("backup path requires a path")
    return path.with_name(path.name + ".bak")


def write_recoverable_file(
    path: Path,
    data: bytes,
    *,
    retain_backup: bool = True,
) -> RecoverableWriteResult:
    """Atomically replace one file while retaining its prior complete version as a backup.

    If the process stops after the old primary rotates but before the new primary
    replaces it, the backup remains complete and can be loaded on the next run.
    """
    if not isinstance(path, Path):
        raise TypeError("recoverable write path must be a path")
    if not isinstance(data, bytes):
        raise TypeError("recoverable write data must be bytes")
    if not isinstance(retain_backup, bool):
        raise TypeError("recoverable write backup setting must be boolean")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return RecoverableWriteFailure(
            RecoverableWriteFailureCode.CREATE_DIRECTORY,
            "could not create the local data directory",
        )
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            temporary_file.write(data)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
    except OSError:
        if temporary_path is not None:
            _remove_temporary(temporary_path)
        return RecoverableWriteFailure(
            RecoverableWriteFailureCode.WRITE_TEMPORARY,
            "could not write local data safely",
        )
    if temporary_path is None:
        raise AssertionError("successful temporary write has no path")
    if retain_backup and path.exists():
        try:
            os.replace(path, backup_path(path))
        except OSError:
            _remove_temporary(temporary_path)
            return RecoverableWriteFailure(
                RecoverableWriteFailureCode.ROTATE_BACKUP,
                "could not retain the previous local data version",
            )
    try:
        os.replace(temporary_path, path)
    except OSError:
        _remove_temporary(temporary_path)
        return RecoverableWriteFailure(
            RecoverableWriteFailureCode.REPLACE_PRIMARY,
            "could not replace local data safely",
        )
    return None


def _remove_temporary(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass
