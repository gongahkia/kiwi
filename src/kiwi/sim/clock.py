"""Fixed-rate authoritative mission clock."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import IntEnum

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.sim.state import MAX_MISSION_TICK, MissionState


class TickRate(IntEnum):
    """The candidate fixed rates permitted by the simulation specification."""

    HZ_20 = 20
    HZ_30 = 30
    HZ_60 = 60


@dataclass(frozen=True, slots=True)
class FixedTickClock:
    """An immutable rate configuration that advances authority one tick at a time."""

    rate: TickRate

    def __post_init__(self) -> None:
        if not isinstance(self.rate, TickRate):
            raise ValueError("fixed tick clock rate must be a TickRate")

    @property
    def tick_duration(self) -> Quantity:
        """Return the exact duration of one authoritative tick."""
        return Quantity(QuantityDimension.DURATION, ExactRational(1, int(self.rate)))

    def advance(self, state: MissionState) -> MissionState:
        """Advance immutable mission state by exactly one authoritative tick."""
        if not isinstance(state, MissionState):
            raise ValueError("clock advance requires mission state")
        if state.tick >= MAX_MISSION_TICK:
            raise ValueError("mission tick advancement exhausted")
        return replace(state, tick=state.tick + 1)
