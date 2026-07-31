from __future__ import annotations

from typing import cast

import pytest

from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import (
    CommandHeader,
    CommandSource,
    ExternalCommand,
    RequestAbort,
    StartMission,
)
from kiwi.sim.events import AbortRequested, MissionStarted
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.state import MissionPhase, MissionState


def _header(tick: int, sequence: int) -> CommandHeader:
    return CommandHeader(tick, sequence, CommandSource.PLAYER)


def test_headless_runner_advances_exact_ticks_and_canonicalises_commands() -> None:
    clock = FixedTickClock(TickRate.HZ_30)
    commands = (
        RequestAbort(_header(1, 2)),
        StartMission(_header(0, 1)),
    )

    result = run_headless(MissionState(), clock, 3, commands)

    assert result.state.tick == 3
    assert result.state.phase is MissionPhase.ABORT_REQUESTED
    assert isinstance(result.events[0], MissionStarted)
    assert isinstance(result.events[1], AbortRequested)
    assert tuple(event.header.tick for event in result.events) == (0, 1)


def test_headless_runner_preserves_zero_tick_state_without_events() -> None:
    state = MissionState(tick=7)

    result = run_headless(state, FixedTickClock(TickRate.HZ_20), 0)

    assert result == HeadlessRun(state, ())


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: run_headless(
                MissionState(),
                FixedTickClock(TickRate.HZ_20),
                1,
                (StartMission(_header(1, 1)),),
            ),
            "executed tick",
        ),
        (
            lambda: run_headless(
                MissionState(),
                FixedTickClock(TickRate.HZ_20),
                -1,
            ),
            "non-negative",
        ),
        (
            lambda: run_headless(
                MissionState(tick=MAX_AUTHORITY_TICK),
                FixedTickClock(TickRate.HZ_20),
                1,
            ),
            "exceed",
        ),
        (
            lambda: run_headless(
                MissionState(),
                FixedTickClock(TickRate.HZ_20),
                1,
                cast(tuple[ExternalCommand, ...], []),
            ),
            "immutable tuple",
        ),
    ),
)
def test_headless_runner_rejects_invalid_run_boundaries(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
