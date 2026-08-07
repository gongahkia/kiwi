"""Versioned local lore-codex persistence outside simulation authority."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from kiwi.app.persistence import RecoverableWriteFailure, backup_path, write_recoverable_file
from kiwi.content.terminal_lore import TERMINAL_LORE_DROPS, terminal_lore_drop
from kiwi.sim.snapshot import PresentationSnapshot

TERMINAL_CODEX_FORMAT = "kiwi-terminal-codex"
TERMINAL_CODEX_VERSION = 1
MAX_TERMINAL_CODEX_BYTES = 65_536


class TerminalCodexLoadFailureCode(StrEnum):
    """Stable failures while loading local codex progress."""

    READ_FAILED = "TC001_READ_FAILED"
    TOO_LARGE = "TC002_TOO_LARGE"
    INVALID_UTF8 = "TC003_INVALID_UTF8"
    INVALID_JSON = "TC004_INVALID_JSON"
    INVALID_STRUCTURE = "TC005_INVALID_STRUCTURE"


@dataclass(frozen=True, slots=True)
class TerminalCodex:
    """Immutable, lexical-ID-ordered local lore progress."""

    unlocked_ids: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.unlocked_ids, tuple):
            raise TypeError("Terminal codex IDs must be immutable")
        if self.unlocked_ids != tuple(sorted(self.unlocked_ids)):
            raise ValueError("Terminal codex IDs must be lexical")
        if len(set(self.unlocked_ids)) != len(self.unlocked_ids):
            raise ValueError("Terminal codex IDs must be unique")
        for lore_id in self.unlocked_ids:
            terminal_lore_drop(lore_id)

    def unlock(self, lore_ids: tuple[str, ...]) -> TerminalCodex:
        """Return the canonical union of current and newly reached shard IDs."""
        if not isinstance(lore_ids, tuple):
            raise TypeError("Terminal codex unlock IDs must be immutable")
        for lore_id in lore_ids:
            terminal_lore_drop(lore_id)
        return TerminalCodex(tuple(sorted(set((*self.unlocked_ids, *lore_ids)))))


@dataclass(frozen=True, slots=True)
class TerminalCodexLoadFailure:
    """A concise non-authoritative codex load failure."""

    code: TerminalCodexLoadFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, TerminalCodexLoadFailureCode):
            raise TypeError("Terminal codex load failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("Terminal codex load failure requires a message")


@dataclass(frozen=True, slots=True)
class TerminalCodexLoadResult:
    """One codex value, optionally recovered from a complete backup."""

    codex: TerminalCodex
    failure: TerminalCodexLoadFailure | None = None
    recovered_from_backup: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.codex, TerminalCodex):
            raise TypeError("Terminal codex load result requires a codex")
        if self.failure is not None and not isinstance(self.failure, TerminalCodexLoadFailure):
            raise TypeError("Terminal codex load result failure is invalid")
        if not isinstance(self.recovered_from_backup, bool):
            raise TypeError("Terminal codex recovery state must be boolean")
        if self.recovered_from_backup and self.failure is None:
            raise ValueError("Terminal codex backup recovery requires an original load failure")


@dataclass(frozen=True, slots=True)
class TerminalCodexSaveResult:
    """One non-throwing codex persistence result."""

    failure: RecoverableWriteFailure | None = None

    def __post_init__(self) -> None:
        if self.failure is not None and not isinstance(self.failure, RecoverableWriteFailure):
            raise TypeError("Terminal codex save result failure is invalid")


def terminal_lore_unlocks(snapshot: PresentationSnapshot) -> tuple[str, ...]:
    """Project policy-reached data shards from one display-safe final snapshot."""
    if not isinstance(snapshot, PresentationSnapshot):
        raise TypeError("Terminal lore unlocks require a presentation snapshot")
    positions = {operative.entity_id: operative.position for operative in snapshot.operatives}
    unlocked: list[str] = []
    for drop in TERMINAL_LORE_DROPS:
        position = positions.get(drop.entity_id)
        if position is None:
            continue
        dx = position.x - drop.position_x
        dy = position.y - drop.position_y
        if dx * dx + dy * dy <= drop.reach_radius * drop.reach_radius:
            unlocked.append(drop.lore_id)
    return tuple(unlocked)


def load_terminal_codex(path: Path) -> TerminalCodex:
    """Load local lore progress, preserving the strict standalone loader contract."""
    result = load_terminal_codex_result(path)
    if result.failure is not None and not result.recovered_from_backup:
        raise ValueError(result.failure.message)
    return result.codex


def load_terminal_codex_result(path: Path) -> TerminalCodexLoadResult:
    """Load local codex data and recover a corrupt or interrupted primary from backup."""
    if not isinstance(path, Path):
        raise TypeError("Terminal codex path must be a path")
    primary = _load_terminal_codex_file(path)
    if primary.failure is None:
        return primary
    backup = _load_terminal_codex_file(backup_path(path))
    if backup.failure is None:
        write_recoverable_file(path, encode_terminal_codex(backup.codex), retain_backup=False)
        return TerminalCodexLoadResult(backup.codex, primary.failure, recovered_from_backup=True)
    if not path.exists() and not backup_path(path).exists():
        return TerminalCodexLoadResult(TerminalCodex())
    return primary


def _load_terminal_codex_file(path: Path) -> TerminalCodexLoadResult:
    try:
        data = path.read_bytes()
    except OSError:
        return _codex_failure(
            TerminalCodexLoadFailureCode.READ_FAILED,
            "Terminal codex could not be read",
        )
    return _decode_terminal_codex(data)


def _decode_terminal_codex(data: bytes) -> TerminalCodexLoadResult:
    if len(data) > MAX_TERMINAL_CODEX_BYTES:
        return _codex_failure(
            TerminalCodexLoadFailureCode.TOO_LARGE,
            "Terminal codex exceeds the byte limit",
        )
    try:
        document = json.loads(data.decode("utf-8"))
    except UnicodeDecodeError:
        return _codex_failure(
            TerminalCodexLoadFailureCode.INVALID_UTF8,
            "Terminal codex is not valid UTF-8",
        )
    except json.JSONDecodeError:
        return _codex_failure(
            TerminalCodexLoadFailureCode.INVALID_JSON,
            "Terminal codex is not valid JSON",
        )
    if not isinstance(document, dict) or set(document) != {"format", "unlocked_ids", "version"}:
        return _codex_failure(
            TerminalCodexLoadFailureCode.INVALID_STRUCTURE,
            "Terminal codex fields are invalid",
        )
    if document["format"] != TERMINAL_CODEX_FORMAT or document["version"] != TERMINAL_CODEX_VERSION:
        return _codex_failure(
            TerminalCodexLoadFailureCode.INVALID_STRUCTURE,
            "Terminal codex format or version is unsupported",
        )
    ids = document["unlocked_ids"]
    if not isinstance(ids, list) or any(not isinstance(item, str) for item in ids):
        return _codex_failure(
            TerminalCodexLoadFailureCode.INVALID_STRUCTURE,
            "Terminal codex lore IDs are invalid",
        )
    try:
        return TerminalCodexLoadResult(TerminalCodex(tuple(ids)))
    except ValueError:
        return _codex_failure(
            TerminalCodexLoadFailureCode.INVALID_STRUCTURE,
            "Terminal codex lore IDs are invalid or unavailable",
        )


def encode_terminal_codex(codex: TerminalCodex) -> bytes:
    """Encode local progress without any authoritative state or replay data."""
    if not isinstance(codex, TerminalCodex):
        raise TypeError("Terminal codex encoding requires a codex")
    return json.dumps(
        {
            "format": TERMINAL_CODEX_FORMAT,
            "unlocked_ids": list(codex.unlocked_ids),
            "version": TERMINAL_CODEX_VERSION,
        },
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def save_terminal_codex(path: Path, codex: TerminalCodex) -> TerminalCodexSaveResult:
    """Persist only local codex IDs at the application IO boundary."""
    if not isinstance(path, Path):
        raise TypeError("Terminal codex path must be a path")
    if not isinstance(codex, TerminalCodex):
        raise TypeError("Terminal codex save requires a codex")
    return TerminalCodexSaveResult(write_recoverable_file(path, encode_terminal_codex(codex)))


def _codex_failure(
    code: TerminalCodexLoadFailureCode,
    message: str,
) -> TerminalCodexLoadResult:
    return TerminalCodexLoadResult(TerminalCodex(), TerminalCodexLoadFailure(code, message))
