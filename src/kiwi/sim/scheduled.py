"""Immutable deterministic queue for future authoritative events."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import MAX_STABLE_ID
from kiwi.sim.limits import MAX_AUTHORITY_TICK


class ScheduledEventKind(StrEnum):
    """The currently schedulable authority event kinds."""

    SCENARIO_TRIGGER = "scenario_trigger"
    LOCKDOWN = "lockdown"


@dataclass(frozen=True, slots=True)
class ScheduledEvent:
    """One future authority event ordered by tick then sequence."""

    tick: int
    sequence: int
    kind: ScheduledEventKind

    def __post_init__(self) -> None:
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("scheduled event tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("scheduled event tick must fit non-negative signed 64-bit range")
        if not isinstance(self.sequence, int) or isinstance(self.sequence, bool):
            raise ValueError("scheduled event sequence must be an integer")
        if not 0 <= self.sequence <= MAX_STABLE_ID:
            raise ValueError("scheduled event sequence must fit non-negative signed 64-bit range")
        if not isinstance(self.kind, ScheduledEventKind):
            raise ValueError("scheduled event kind must be a ScheduledEventKind")


@dataclass(frozen=True, slots=True)
class ScheduledEventQueue:
    """Immutable canonical pending events and their next deterministic sequence."""

    pending: tuple[ScheduledEvent, ...] = ()
    next_sequence: int = 0

    def __post_init__(self) -> None:
        if not isinstance(self.pending, tuple):
            raise ValueError("scheduled queue entries must be an immutable tuple")
        if not isinstance(self.next_sequence, int) or isinstance(self.next_sequence, bool):
            raise ValueError("scheduled queue sequence must be an integer")
        if not 0 <= self.next_sequence <= MAX_STABLE_ID + 1:
            raise ValueError("scheduled queue sequence must fit non-negative signed 64-bit range")
        previous_key: tuple[int, int] | None = None
        sequences: set[int] = set()
        for event in self.pending:
            if not isinstance(event, ScheduledEvent):
                raise ValueError("scheduled queue entries must be scheduled events")
            key = (event.tick, event.sequence)
            if previous_key is not None and key <= previous_key:
                raise ValueError("scheduled queue entries must be unique and tick-sequence ordered")
            if event.sequence in sequences:
                raise ValueError("scheduled queue event sequences must be unique")
            if event.sequence >= self.next_sequence:
                raise ValueError("scheduled queue events must precede the next sequence")
            sequences.add(event.sequence)
            previous_key = key

    def schedule(
        self,
        tick: int,
        kind: ScheduledEventKind,
    ) -> tuple[ScheduledEvent, ScheduledEventQueue]:
        """Allocate and insert one event without depending on insertion order."""
        if not isinstance(tick, int) or isinstance(tick, bool):
            raise ValueError("scheduled event tick must be an integer")
        if not 0 <= tick <= MAX_AUTHORITY_TICK:
            raise ValueError("scheduled event tick must fit non-negative signed 64-bit range")
        if not isinstance(kind, ScheduledEventKind):
            raise ValueError("scheduled event kind must be a ScheduledEventKind")
        if self.next_sequence > MAX_STABLE_ID:
            raise ValueError("scheduled event sequence allocation exhausted")
        event = ScheduledEvent(tick=tick, sequence=self.next_sequence, kind=kind)
        pending = tuple(sorted((*self.pending, event), key=lambda item: (item.tick, item.sequence)))
        return event, ScheduledEventQueue(pending=pending, next_sequence=self.next_sequence + 1)

    def due_at(self, tick: int) -> tuple[tuple[ScheduledEvent, ...], ScheduledEventQueue]:
        """Remove and return events due at one exact authoritative tick."""
        if not isinstance(tick, int) or isinstance(tick, bool):
            raise ValueError("scheduled queue lookup tick must be an integer")
        if not 0 <= tick <= MAX_AUTHORITY_TICK:
            raise ValueError(
                "scheduled queue lookup tick must fit non-negative signed 64-bit range"
            )
        due = tuple(event for event in self.pending if event.tick == tick)
        pending = tuple(event for event in self.pending if event.tick != tick)
        return due, ScheduledEventQueue(pending=pending, next_sequence=self.next_sequence)
