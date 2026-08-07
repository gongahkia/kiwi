"""Versioned local-only completion state for the Terminal onboarding drill."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

_FORMAT = "kiwi-terminal-progress"
_VERSION = 1


@dataclass(frozen=True, slots=True)
class TerminalProgress:
    """The deliberately small durable progression surface for local practice."""

    onboarding_complete: bool = False

    def __post_init__(self) -> None:
        if not isinstance(self.onboarding_complete, bool):
            raise TypeError("Terminal onboarding completion must be boolean")

    def complete_onboarding(self) -> TerminalProgress:
        """Mark the safe first-link drill complete without changing authority."""
        return TerminalProgress(True)


def load_terminal_progress(path: Path) -> TerminalProgress:
    """Load validated local progress, treating absent or malformed data as new progress."""
    if not isinstance(path, Path):
        raise TypeError("Terminal progress path must be a path")
    try:
        raw = path.read_text(encoding="utf-8")
        value = json.loads(raw)
    except (OSError, json.JSONDecodeError):
        return TerminalProgress()
    if not isinstance(value, dict):
        return TerminalProgress()
    if value.get("format") != _FORMAT or value.get("version") != _VERSION:
        return TerminalProgress()
    complete = value.get("onboarding_complete")
    return TerminalProgress(complete) if isinstance(complete, bool) else TerminalProgress()


def save_terminal_progress(path: Path, progress: TerminalProgress) -> None:
    """Persist one validated progress value through the application boundary."""
    if not isinstance(path, Path):
        raise TypeError("Terminal progress path must be a path")
    if not isinstance(progress, TerminalProgress):
        raise TypeError("Terminal progress value is invalid")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "format": _FORMAT,
                "version": _VERSION,
                "onboarding_complete": progress.onboarding_complete,
            },
            sort_keys=True,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )
