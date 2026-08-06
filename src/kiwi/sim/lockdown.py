"""Canonical one-shot lockdown state for timed scenario pressure."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.ids import EventId
from kiwi.sim.limits import MAX_AUTHORITY_TICK


@dataclass(frozen=True, slots=True)
class LockdownState:
    """The retained one-shot lockdown transition and its canonical provenance."""

    active: bool = False
    activation_tick: int | None = None
    activation_event_id: EventId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.active, bool):
            raise ValueError("lockdown active flag must be boolean")
        if not self.active and (
            self.activation_tick is not None or self.activation_event_id is not None
        ):
            raise ValueError("inactive lockdown cannot retain activation provenance")
        if self.active and (
            not isinstance(self.activation_tick, int)
            or isinstance(self.activation_tick, bool)
            or not 0 <= self.activation_tick <= MAX_AUTHORITY_TICK
        ):
            raise ValueError("active lockdown requires an activation tick")
        if self.active and not isinstance(self.activation_event_id, EventId):
            raise ValueError("active lockdown requires an activation event ID")
