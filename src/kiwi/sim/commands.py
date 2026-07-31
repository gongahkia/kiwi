"""Typed external authority commands and their canonical order."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import MAX_STABLE_ID, EntityId
from kiwi.sim.limits import MAX_AUTHORITY_TICK


class CommandSource(StrEnum):
    """The recorded boundary that introduced an authority command."""

    PLAYER = "player"
    SCENARIO = "scenario"


@dataclass(frozen=True, slots=True)
class CommandHeader:
    """Canonical timestamp and globally unique order for one command."""

    tick: int
    sequence: int
    source: CommandSource

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("command tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("command tick must fit non-negative signed 64-bit range")
        if not isinstance(self.sequence, int) or isinstance(self.sequence, bool):
            raise ValueError("command sequence must be an integer")
        if not 0 <= self.sequence <= MAX_STABLE_ID:
            raise ValueError("command sequence must fit non-negative signed 64-bit range")
        if not isinstance(self.source, CommandSource):
            raise ValueError("command source must be a CommandSource")


@dataclass(frozen=True, slots=True)
class SignalName:
    """A future content-defined strategic signal identifier."""

    value: str

    def __post_init__(self) -> None:
        if (
            not isinstance(self.value, str)
            or not self.value
            or not self.value.isascii()
            or not self.value.isidentifier()
            or self.value != self.value.lower()
        ):
            raise ValueError("signal name must be a non-empty lowercase ASCII identifier")


@dataclass(frozen=True, slots=True)
class StartMission:
    """Request the transition from prepared to active mission state."""

    header: CommandHeader

    def __post_init__(self) -> None:
        _require_command_header(self.header)


@dataclass(frozen=True, slots=True)
class RequestAbort:
    """Request an authorised mission abort without direct entity control."""

    header: CommandHeader

    def __post_init__(self) -> None:
        _require_command_header(self.header)


@dataclass(frozen=True, slots=True)
class IssueSignal:
    """Send a content-defined strategic signal to the squad or one entity."""

    header: CommandHeader
    signal: SignalName
    target: EntityId | None = None

    def __post_init__(self) -> None:
        _require_command_header(self.header)
        if not isinstance(self.signal, SignalName):
            raise ValueError("signal command requires a signal name")
        if self.target is not None and not isinstance(self.target, EntityId):
            raise ValueError("signal command target must be an entity ID or None")


ExternalCommand = StartMission | RequestAbort | IssueSignal


def canonical_command_order(commands: Iterable[ExternalCommand]) -> tuple[ExternalCommand, ...]:
    """Sort commands by `(tick, sequence)` and reject duplicate global sequences."""
    ordered: list[ExternalCommand] = []
    sequences: set[int] = set()
    for command in commands:
        if not isinstance(command, (StartMission, RequestAbort, IssueSignal)):
            raise ValueError("canonical command ordering requires external commands")
        sequence = command.header.sequence
        if sequence in sequences:
            raise ValueError("command sequences must be globally unique")
        sequences.add(sequence)
        ordered.append(command)
    return tuple(
        sorted(ordered, key=lambda command: (command.header.tick, command.header.sequence))
    )


def _require_command_header(value: object) -> None:
    if not isinstance(value, CommandHeader):
        raise ValueError("command requires a command header")
