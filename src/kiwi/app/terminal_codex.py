"""Versioned local lore-codex persistence outside simulation authority."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from kiwi.content.terminal_lore import TERMINAL_LORE_DROPS, terminal_lore_drop
from kiwi.sim.snapshot import PresentationSnapshot

TERMINAL_CODEX_FORMAT = "kiwi-terminal-codex"
TERMINAL_CODEX_VERSION = 1
MAX_TERMINAL_CODEX_BYTES = 65_536


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
    """Load local lore progress; an absent file is a new empty codex."""
    if not isinstance(path, Path):
        raise TypeError("Terminal codex path must be a path")
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        return TerminalCodex()
    if len(data) > MAX_TERMINAL_CODEX_BYTES:
        raise ValueError("Terminal codex exceeds the byte limit")
    try:
        document = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("Terminal codex is invalid JSON") from error
    if not isinstance(document, dict) or set(document) != {"format", "unlocked_ids", "version"}:
        raise ValueError("Terminal codex fields are invalid")
    if document["format"] != TERMINAL_CODEX_FORMAT or document["version"] != TERMINAL_CODEX_VERSION:
        raise ValueError("Terminal codex format or version is unsupported")
    ids = document["unlocked_ids"]
    if not isinstance(ids, list) or any(not isinstance(item, str) for item in ids):
        raise ValueError("Terminal codex lore IDs are invalid")
    return TerminalCodex(tuple(ids))


def save_terminal_codex(path: Path, codex: TerminalCodex) -> None:
    """Persist only local codex IDs at the application IO boundary."""
    if not isinstance(path, Path):
        raise TypeError("Terminal codex path must be a path")
    if not isinstance(codex, TerminalCodex):
        raise TypeError("Terminal codex save requires a codex")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "format": TERMINAL_CODEX_FORMAT,
                "unlocked_ids": list(codex.unlocked_ids),
                "version": TERMINAL_CODEX_VERSION,
            },
            separators=(",", ":"),
            sort_keys=True,
        ),
        encoding="utf-8",
    )
