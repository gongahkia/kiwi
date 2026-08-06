"""Original lore drops placed in the Terminal netspace scenario."""

from __future__ import annotations

from dataclasses import dataclass


def _identifier(value: str) -> bool:
    return bool(value) and all(
        character.isascii() and (character.islower() or character.isdigit() or character == "_")
        for character in value
    )


@dataclass(frozen=True, slots=True)
class TerminalLoreDrop:
    """One immutable data shard addressed by a stable content identifier."""

    lore_id: str
    title: str
    body: tuple[str, ...]
    entity_id: int
    position_x: int
    position_y: int
    reach_radius: int

    def __post_init__(self) -> None:
        if not _identifier(self.lore_id):
            raise ValueError("Terminal lore ID must be a lowercase ASCII identifier")
        if not isinstance(self.title, str) or not self.title:
            raise ValueError("Terminal lore title must be text")
        if (
            not isinstance(self.body, tuple)
            or not self.body
            or any(not isinstance(line, str) or not line for line in self.body)
        ):
            raise ValueError("Terminal lore body must be non-empty immutable text")
        if (
            not isinstance(self.entity_id, int)
            or isinstance(self.entity_id, bool)
            or self.entity_id <= 0
        ):
            raise ValueError("Terminal lore entity ID must be positive")
        if any(
            not isinstance(value, int) or isinstance(value, bool)
            for value in (self.position_x, self.position_y, self.reach_radius)
        ):
            raise TypeError("Terminal lore coordinates and reach radius must be integers")
        if self.reach_radius <= 0:
            raise ValueError("Terminal lore reach radius must be positive")


TERMINAL_LORE_DROPS = (
    TerminalLoreDrop(
        "subnet_saltline",
        "SALT LINE // recovered relay memo",
        (
            "A relay under Night City carries old debt ledgers beside routine traffic.",
            "The sender calls this path a salt line: cheap, quiet, and never clean.",
            "No names survived the wipe. Only a route, a warning, and a checksum remain.",
        ),
        1,
        800,
        0,
        650,
    ),
    TerminalLoreDrop(
        "arasaka_blackice_note",
        "ARASAKA // black ICE field note",
        (
            "Corporate ICE does not need to understand a netrunner to hurt one.",
            "It only needs a confident route, a late warning, and an exposed daemon.",
            "The note ends before the author explains how they got out.",
        ),
        1,
        1_600,
        0,
        500,
    ),
)


def terminal_lore_drop(lore_id: str) -> TerminalLoreDrop:
    """Return one shipped lore entry by its explicit stable ID."""
    if not _identifier(lore_id):
        raise ValueError("Terminal lore ID must be a lowercase ASCII identifier")
    for drop in TERMINAL_LORE_DROPS:
        if drop.lore_id == lore_id:
            return drop
    raise ValueError("Terminal lore ID is unavailable")
