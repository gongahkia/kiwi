from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import EntityId, EventId
from kiwi.dsl.runtime_values import IntegerValue, ListValue, RecordValue, StringValue
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, IssueSignal, SignalName, StartMission
from kiwi.sim.events import CommandRejected, CommandRejectionReason, MissionStarted, SignalIssued
from kiwi.sim.observations import build_runtime_observations, observation_runtime_value
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.signals import (
    SIGNAL_RECORD_TYPE,
    SignalObservation,
    SignalStore,
    add_signal,
    discard_signals_before,
    signal_runtime_value,
    signals_for,
    signals_runtime_value,
)
from kiwi.sim.state import MissionState, add_entity


def test_signal_store_projects_squad_and_targeted_values_in_command_order() -> None:
    targeted = SignalObservation(
        SignalName("hold"), 4, 2, CommandSource.PLAYER, EntityId(2), EventId(2)
    )
    squad = SignalObservation(SignalName("advance"), 4, 1, CommandSource.SCENARIO, None, EventId(1))
    store = add_signal(add_signal(SignalStore(), targeted), squad)

    assert store.signals == (squad, targeted)
    assert signals_for(store, EntityId(1), 4) == (squad,)
    assert signals_for(store, EntityId(2), 4) == (squad, targeted)
    assert signals_for(store, EntityId(2), 5) == ()
    assert discard_signals_before(store, 5) == SignalStore()
    assert signal_runtime_value(squad) == RecordValue(
        SIGNAL_RECORD_TYPE,
        ("name", "tick"),
        (StringValue("advance"), IntegerValue(4)),
    )
    assert signals_runtime_value((squad, targeted)) == ListValue(
        (signal_runtime_value(squad), signal_runtime_value(targeted))
    )


def test_reducer_accepts_active_signals_and_rejects_unknown_targets() -> None:
    state, first = add_entity(MissionState(), WorldPosition(WorldSubunits(0), WorldSubunits(0)))
    state, second = add_entity(state, WorldPosition(WorldSubunits(1), WorldSubunits(1)))
    clock = FixedTickClock(TickRate.HZ_30)

    started = reduce_one_tick(
        state,
        clock,
        (
            StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),
            IssueSignal(CommandHeader(0, 1, CommandSource.PLAYER), SignalName("advance")),
            IssueSignal(
                CommandHeader(0, 2, CommandSource.PLAYER),
                SignalName("hold"),
                second.entity_id,
            ),
        ),
    )

    assert tuple(type(event) for event in started.events) == (
        MissionStarted,
        SignalIssued,
        SignalIssued,
    )
    assert tuple(
        (
            signal.signal.value,
            signal.tick,
            signal.command_sequence,
            signal.source,
            signal.target_entity_id,
            signal.provenance_event_id.value,
        )
        for signal in started.state.signals.signals
    ) == (
        ("advance", 0, 1, CommandSource.PLAYER, None, 2),
        ("hold", 0, 2, CommandSource.PLAYER, second.entity_id, 3),
    )
    assert signals_for(started.state.signals, first.entity_id, 0) == (
        started.state.signals.signals[0],
    )
    assert signals_for(started.state.signals, second.entity_id, 0) == started.state.signals.signals

    rejected = reduce_one_tick(
        started.state,
        clock,
        (IssueSignal(CommandHeader(1, 3, CommandSource.PLAYER), SignalName("hold"), EntityId(99)),),
    )

    assert isinstance(rejected.events[0], CommandRejected)
    assert rejected.events[0].reason is CommandRejectionReason.SIGNAL_TARGET_NOT_FOUND
    assert rejected.state.signals == SignalStore()


def test_runtime_observations_hide_targeted_signals_from_other_entities() -> None:
    initial, first = add_entity(
        MissionState(tick=4), WorldPosition(WorldSubunits(0), WorldSubunits(0))
    )
    state, second = add_entity(initial, WorldPosition(WorldSubunits(1), WorldSubunits(1)))
    event_id, allocator = state.id_allocator.allocate_event()
    signals = SignalStore(
        (
            SignalObservation(
                SignalName("hold"),
                4,
                0,
                CommandSource.PLAYER,
                second.entity_id,
                event_id,
            ),
        )
    )
    state = replace(state, signals=signals, id_allocator=allocator)

    observations = build_runtime_observations(state)

    assert observations[0].signals == ()
    assert observations[1].signals == signals.signals
    assert observation_runtime_value(observations[1]).field_value("signals") == ListValue(
        (signal_runtime_value(signals.signals[0]),)
    )


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: SignalObservation(
                SignalName("hold"),
                0,
                0,
                CommandSource.PLAYER,
                None,
                object(),  # type: ignore[arg-type]
            ),
            "event ID",
        ),
        (lambda: SignalStore([]), "immutable tuple"),  # type: ignore[arg-type]
        (
            lambda: signals_runtime_value((object(),)),  # type: ignore[arg-type]
            "signal observations",
        ),
    ),
)
def test_signal_values_reject_invalid_inputs(factory: object, message: str) -> None:
    with pytest.raises((TypeError, ValueError), match=message):
        factory()  # type: ignore[operator]
