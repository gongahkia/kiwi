from __future__ import annotations

import pytest

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.state import MAX_MISSION_TICK, MissionState


@pytest.mark.parametrize(
    ("rate", "duration"),
    (
        (TickRate.HZ_20, ExactRational(1, 20)),
        (TickRate.HZ_30, ExactRational(1, 30)),
        (TickRate.HZ_60, ExactRational(1, 60)),
    ),
)
def test_fixed_tick_clock_exposes_exact_duration(rate: TickRate, duration: ExactRational) -> None:
    assert FixedTickClock(rate).tick_duration == Quantity(QuantityDimension.DURATION, duration)


def test_fixed_tick_clock_advances_one_immutable_authoritative_tick() -> None:
    clock = FixedTickClock(TickRate.HZ_30)
    initial = MissionState(tick=7)

    advanced = clock.advance(initial)

    assert initial.tick == 7
    assert advanced.tick == 8
    assert clock.advance(MissionState()) == MissionState(tick=1)


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: FixedTickClock(30), "TickRate"),  # type: ignore[arg-type]
        (lambda: FixedTickClock(TickRate.HZ_20).advance(object()), "mission state"),  # type: ignore[arg-type]
        (
            lambda: FixedTickClock(TickRate.HZ_20).advance(MissionState(tick=MAX_MISSION_TICK)),
            "exhausted",
        ),
    ),
)
def test_fixed_tick_clock_rejects_invalid_inputs_and_overflow(
    factory: object, message: str
) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
