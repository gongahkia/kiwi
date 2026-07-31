"""Closed canonical authority event records."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EventId
from kiwi.sim.commands import ExternalCommand, IssueSignal, RequestAbort, StartMission
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.randomness import RandomDraw
from kiwi.sim.scheduled import ScheduledEvent


class EventKind(StrEnum):
    """The current closed set of canonical authority event variants."""

    MISSION_STARTED = "mission_started"
    ABORT_REQUESTED = "abort_requested"
    SIGNAL_ISSUED = "signal_issued"
    SCHEDULED_TRIGGER_FIRED = "scheduled_trigger_fired"
    RANDOM_DRAW_RECORDED = "random_draw_recorded"
    COMMAND_REJECTED = "command_rejected"


class CommandRejectionReason(StrEnum):
    """Stable reasons the initial reducer can reject an external command."""

    MISSION_NOT_PREPARED = "mission_not_prepared"
    MISSION_NOT_ACTIVE = "mission_not_active"
    SIGNALS_UNAVAILABLE = "signals_unavailable"


@dataclass(frozen=True, slots=True)
class EventHeader:
    """Stable event identity, timestamp, and canonical causal parents."""

    event_id: EventId
    tick: int
    parent_event_ids: tuple[EventId, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.event_id, EventId):
            raise ValueError("event header requires an event ID")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("event tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("event tick must fit non-negative signed 64-bit range")
        if not isinstance(self.parent_event_ids, tuple):
            raise ValueError("event parent IDs must be an immutable tuple")
        previous_id = 0
        for parent_id in self.parent_event_ids:
            if not isinstance(parent_id, EventId):
                raise ValueError("event parent IDs must contain event IDs")
            if parent_id.value <= previous_id:
                raise ValueError("event parent IDs must be unique and ascending")
            if parent_id.value >= self.event_id.value:
                raise ValueError("event parent IDs must precede the event ID")
            previous_id = parent_id.value


@dataclass(frozen=True, slots=True)
class MissionStarted:
    """The recorded application of a start-mission command."""

    header: EventHeader
    command: StartMission

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, StartMission):
            raise ValueError("mission started event requires a start mission command")
        _require_matching_tick(self.header, self.command.header.tick)


@dataclass(frozen=True, slots=True)
class AbortRequested:
    """The recorded application of an abort request command."""

    header: EventHeader
    command: RequestAbort

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, RequestAbort):
            raise ValueError("abort event requires an abort request command")
        _require_matching_tick(self.header, self.command.header.tick)


@dataclass(frozen=True, slots=True)
class SignalIssued:
    """The recorded application of a high-level signal command."""

    header: EventHeader
    command: IssueSignal

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, IssueSignal):
            raise ValueError("signal event requires a signal command")
        _require_matching_tick(self.header, self.command.header.tick)


@dataclass(frozen=True, slots=True)
class ScheduledTriggerFired:
    """The recorded dequeue of one scheduled scenario trigger."""

    header: EventHeader
    scheduled_event: ScheduledEvent

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.scheduled_event, ScheduledEvent):
            raise ValueError("scheduled trigger event requires a scheduled event")
        _require_matching_tick(self.header, self.scheduled_event.tick)


@dataclass(frozen=True, slots=True)
class RandomDrawRecorded:
    """The recorded use of one named deterministic random draw."""

    header: EventHeader
    draw: RandomDraw

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.draw, RandomDraw):
            raise ValueError("random draw event requires a random draw")


@dataclass(frozen=True, slots=True)
class CommandRejected:
    """A structured record of an invalid or unsupported command application."""

    header: EventHeader
    command: ExternalCommand
    reason: CommandRejectionReason

    def __post_init__(self) -> None:
        _require_header(self.header)
        if not isinstance(self.command, (StartMission, RequestAbort, IssueSignal)):
            raise ValueError("command rejection event requires an external command")
        if not isinstance(self.reason, CommandRejectionReason):
            raise ValueError("command rejection event requires a rejection reason")
        _require_matching_tick(self.header, self.command.header.tick)


CanonicalEvent = (
    MissionStarted
    | AbortRequested
    | SignalIssued
    | ScheduledTriggerFired
    | RandomDrawRecorded
    | CommandRejected
)


def event_kind(event: CanonicalEvent) -> EventKind:
    """Return the stable tag for a closed event variant."""
    if isinstance(event, MissionStarted):
        return EventKind.MISSION_STARTED
    if isinstance(event, AbortRequested):
        return EventKind.ABORT_REQUESTED
    if isinstance(event, SignalIssued):
        return EventKind.SIGNAL_ISSUED
    if isinstance(event, ScheduledTriggerFired):
        return EventKind.SCHEDULED_TRIGGER_FIRED
    if isinstance(event, RandomDrawRecorded):
        return EventKind.RANDOM_DRAW_RECORDED
    if isinstance(event, CommandRejected):
        return EventKind.COMMAND_REJECTED
    raise ValueError("event kind requires a canonical event")


def canonical_event_order(events: Iterable[CanonicalEvent]) -> tuple[CanonicalEvent, ...]:
    """Sort canonical events by `(tick, event ID)` and reject reused IDs."""
    ordered: list[CanonicalEvent] = []
    event_ids: set[int] = set()
    for event in events:
        if not isinstance(
            event,
            (
                MissionStarted,
                AbortRequested,
                SignalIssued,
                ScheduledTriggerFired,
                RandomDrawRecorded,
                CommandRejected,
            ),
        ):
            raise ValueError("canonical event ordering requires canonical events")
        event_id = event.header.event_id.value
        if event_id in event_ids:
            raise ValueError("canonical event IDs must be globally unique")
        event_ids.add(event_id)
        ordered.append(event)
    return tuple(
        sorted(ordered, key=lambda event: (event.header.tick, event.header.event_id.value))
    )


def _require_header(value: object) -> None:
    if not isinstance(value, EventHeader):
        raise ValueError("event requires an event header")


def _require_matching_tick(header: EventHeader, source_tick: int) -> None:
    if header.tick != source_tick:
        raise ValueError("event tick must match its source tick")
