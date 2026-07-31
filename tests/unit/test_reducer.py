from __future__ import annotations

from dataclasses import replace
from typing import cast

import pytest

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import (
    CommandHeader,
    CommandSource,
    ExternalCommand,
    IssueSignal,
    RequestAbort,
    SignalName,
    StartMission,
)
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactSighting,
    advance_contacts,
    apply_contact_sightings,
)
from kiwi.sim.events import (
    AbortRequested,
    CanonicalEvent,
    CommandRejected,
    CommandRejectionReason,
    MissionStarted,
    ScheduledTriggerFired,
)
from kiwi.sim.reducer import TickResult, reduce_one_tick
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.state import MissionPhase, MissionState, add_entity


def header(sequence: int) -> CommandHeader:
    return CommandHeader(tick=0, sequence=sequence, source=CommandSource.PLAYER)


def test_reducer_applies_current_commands_dequeues_events_and_advances_once() -> None:
    scheduled, queue = MissionState().scheduled_events.schedule(
        0, ScheduledEventKind.SCENARIO_TRIGGER
    )
    state = MissionState(scheduled_events=queue)
    commands = (
        IssueSignal(header(2), SignalName("hold")),
        StartMission(header(1)),
    )

    result = reduce_one_tick(state, FixedTickClock(TickRate.HZ_30), commands)

    assert result.state.tick == 1
    assert result.state.phase is MissionPhase.ACTIVE
    assert result.state.scheduled_events.pending == ()
    assert isinstance(result.events[0], MissionStarted)
    assert isinstance(result.events[1], CommandRejected)
    assert result.events[1].reason is CommandRejectionReason.SIGNALS_UNAVAILABLE
    assert isinstance(result.events[2], ScheduledTriggerFired)
    assert result.events[2].scheduled_event == scheduled
    assert tuple(event.header.event_id.value for event in result.events) == (1, 2, 3)


def test_reducer_applies_abort_on_the_next_active_tick() -> None:
    clock = FixedTickClock(TickRate.HZ_20)
    active = reduce_one_tick(MissionState(), clock, (StartMission(header(0)),)).state
    abort = RequestAbort(CommandHeader(tick=1, sequence=1, source=CommandSource.PLAYER))

    result = reduce_one_tick(active, clock, (abort,))

    assert result.state.phase is MissionPhase.ABORT_REQUESTED
    assert isinstance(result.events[0], AbortRequested)


def test_active_reducer_advances_persisted_contact_lifecycle() -> None:
    state, owner = add_entity(
        MissionState(tick=1, phase=MissionPhase.ACTIVE),
        WorldPosition(WorldSubunits(0), WorldSubunits(0)),
    )
    resolved_contacts = advance_contacts(state.contacts, state.tick)
    contacts, allocator = apply_contact_sightings(
        resolved_contacts,
        state.id_allocator,
        state.tick,
        (
            ContactSighting(
                owner.entity_id,
                WorldPosition(WorldSubunits(200), WorldSubunits(300)),
                WorldSubunits(300),
                ContactConfidence(200),
            ),
        ),
    )
    state = replace(state, contacts=contacts, id_allocator=allocator)
    clock = FixedTickClock(TickRate.HZ_30)

    first = reduce_one_tick(state, clock)
    second = reduce_one_tick(first.state, clock)

    assert first.state.contacts.estimates[0].confidence == ContactConfidence(200)
    assert second.state.contacts.lifecycle_tick == 2
    assert second.state.contacts.estimates[0].confidence == ContactConfidence(100)


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: reduce_one_tick(
                MissionState(),
                FixedTickClock(TickRate.HZ_20),
                (StartMission(CommandHeader(1, 0, CommandSource.SCENARIO)),),
            ),
            "current mission tick",
        ),
        (
            lambda: reduce_one_tick(
                MissionState(),
                FixedTickClock(TickRate.HZ_20),
                cast(tuple[ExternalCommand, ...], []),
            ),
            "immutable tuple",
        ),
        (
            lambda: TickResult(MissionState(), cast(tuple[CanonicalEvent, ...], [])),
            "immutable tuple",
        ),
    ),
)
def test_reducer_rejects_noncanonical_tick_inputs(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
