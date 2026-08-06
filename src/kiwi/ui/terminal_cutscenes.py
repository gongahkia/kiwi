"""Bounded, data-driven terminal cutscene definitions."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class TerminalCutsceneBeatKind(StrEnum):
    TERMINAL_TEXT = "terminal_text"
    SPRITE = "sprite"
    SOUND = "sound"
    HOLD = "hold"
    TRANSITION = "transition"


def _identifier(value: str) -> bool:
    return bool(value) and all(
        character.isascii() and (character.islower() or character.isdigit() or character == "_")
        for character in value
    )


@dataclass(frozen=True, slots=True)
class TerminalCutsceneBeat:
    """One finite visual or audio beat with renderer-only timing."""

    kind: TerminalCutsceneBeatKind
    value: str
    duration_milliseconds: int

    def __post_init__(self) -> None:
        if not isinstance(self.kind, TerminalCutsceneBeatKind):
            raise TypeError("Terminal cutscene beat kind is invalid")
        if not isinstance(self.value, str):
            raise TypeError("Terminal cutscene beat value must be text")
        if (
            not isinstance(self.duration_milliseconds, int)
            or isinstance(self.duration_milliseconds, bool)
            or not 0 < self.duration_milliseconds <= 30_000
        ):
            raise ValueError("Terminal cutscene beat duration must be bounded and positive")


@dataclass(frozen=True, slots=True)
class TerminalCutscene:
    """One named replayable sequence whose data contains no authority state."""

    cutscene_id: str
    title: str
    beats: tuple[TerminalCutsceneBeat, ...]

    def __post_init__(self) -> None:
        if not _identifier(self.cutscene_id):
            raise ValueError("Terminal cutscene ID must be a lowercase ASCII identifier")
        if not isinstance(self.title, str) or not self.title:
            raise ValueError("Terminal cutscene title must be text")
        if not isinstance(self.beats, tuple) or not self.beats:
            raise ValueError("Terminal cutscene must have immutable beats")
        if any(not isinstance(beat, TerminalCutsceneBeat) for beat in self.beats):
            raise TypeError("Terminal cutscene beats are invalid")

    @property
    def duration_milliseconds(self) -> int:
        return sum(beat.duration_milliseconds for beat in self.beats)

    def visible_beats(self, elapsed_milliseconds: int) -> tuple[TerminalCutsceneBeat, ...]:
        """Return beats completed by one bounded renderer clock value."""
        if (
            not isinstance(elapsed_milliseconds, int)
            or isinstance(elapsed_milliseconds, bool)
            or elapsed_milliseconds < 0
        ):
            raise ValueError("Terminal cutscene elapsed time must be non-negative")
        elapsed = min(elapsed_milliseconds, self.duration_milliseconds)
        visible: list[TerminalCutsceneBeat] = []
        for beat in self.beats:
            if elapsed <= 0:
                break
            visible.append(beat)
            elapsed -= beat.duration_milliseconds
        return tuple(visible)


TERMINAL_CUTSCENES = (
    TerminalCutscene(
        "terminal_boot",
        "KIWI // terminal boot",
        (
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.SPRITE, "operator_seated", 550),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.SOUND, "terminal_power", 180),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.TERMINAL_TEXT, "seat link detected", 800),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.TERMINAL_TEXT, "KIWI // ready", 1_100),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.TRANSITION, "input_setup", 1),
        ),
    ),
    TerminalCutscene(
        "terminal_deploy",
        "KIWI // jacking in",
        (
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.SPRITE, "operator_linked", 400),
            TerminalCutsceneBeat(
                TerminalCutsceneBeatKind.TERMINAL_TEXT, "mapping hostile mainframe", 700
            ),
            TerminalCutsceneBeat(
                TerminalCutsceneBeatKind.TERMINAL_TEXT, "deploying daemon bundle", 900
            ),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.TRANSITION, "live_preview", 1),
        ),
    ),
    TerminalCutscene(
        "payload_exfiltration",
        "KIWI // payload exfiltration",
        (
            TerminalCutsceneBeat(
                TerminalCutsceneBeatKind.TERMINAL_TEXT, "payload integrity verified", 900
            ),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.SOUND, "payload_unlock", 160),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.HOLD, "", 500),
        ),
    ),
    TerminalCutscene(
        "trace_lockdown",
        "KIWI // trace lockdown",
        (
            TerminalCutsceneBeat(
                TerminalCutsceneBeatKind.TERMINAL_TEXT, "black ICE acquired the route", 900
            ),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.SOUND, "trace_lock", 160),
            TerminalCutsceneBeat(TerminalCutsceneBeatKind.HOLD, "", 500),
        ),
    ),
)


def terminal_cutscene(cutscene_id: str) -> TerminalCutscene:
    """Return one shipped sequence by explicit stable content ID."""
    if not _identifier(cutscene_id):
        raise ValueError("Terminal cutscene ID must be a lowercase ASCII identifier")
    for cutscene in TERMINAL_CUTSCENES:
        if cutscene.cutscene_id == cutscene_id:
            return cutscene
    raise ValueError("Terminal cutscene ID is unavailable")
