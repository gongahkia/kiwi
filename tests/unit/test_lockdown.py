from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.events import LockdownActivated, ObjectiveExtracted, ScheduledTriggerFired
from kiwi.sim.hashing import decode_canonical_state, encode_canonical_state, hash_canonical_state
from kiwi.sim.objectives import ObjectiveStatus, ObjectiveStore, RetrievalObjective
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.runner import HeadlessRun
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.state import MissionPhase, MissionState, add_entity
from kiwi.trace.capture import capture_run_trace
from kiwi.trace.model import TraceEdgeKind, TraceLevel, WorldEventTrace
from kiwi.trace.retention import TraceRetentionPolicy


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def _retrieved_extraction_state(with_lockdown_timer: bool) -> MissionState:
    state, entity = add_entity(MissionState(phase=MissionPhase.ACTIVE), _position(1_050, 1_050))
    retrieval_event_id, allocator = state.id_allocator.allocate_event()
    objective_id, allocator = allocator.allocate_objective()
    objective = RetrievalObjective(
        objective_id,
        _rectangle(0, 0, 100, 100),
        _rectangle(1_000, 1_000, 1_100, 1_100),
        (entity.entity_id,),
        ObjectiveStatus.RETRIEVED,
        entity.entity_id,
        retrieval_event_id,
    )
    state = replace(state, id_allocator=allocator, objectives=ObjectiveStore((objective,)))
    if not with_lockdown_timer:
        return state
    _, scheduled_events = state.scheduled_events.schedule(0, ScheduledEventKind.LOCKDOWN)
    return replace(state, scheduled_events=scheduled_events)


def test_lockdown_timer_activates_before_objective_extraction_and_round_trips() -> None:
    result = reduce_one_tick(_retrieved_extraction_state(True), FixedTickClock(TickRate.HZ_30))

    assert isinstance(result.events[0], ScheduledTriggerFired)
    assert isinstance(result.events[1], LockdownActivated)
    trigger = result.events[0]
    activated = result.events[1]
    assert activated.header.parent_event_ids == (trigger.header.event_id,)
    assert result.state.lockdown.active
    assert result.state.lockdown.activation_tick == 0
    assert result.state.lockdown.activation_event_id == activated.header.event_id
    assert result.state.objectives.entries[0].status is ObjectiveStatus.RETRIEVED
    assert decode_canonical_state(encode_canonical_state(result.state)) == result.state
    trace = capture_run_trace(
        HeadlessRun(result.state, result.events),
        hash_canonical_state(result.state),
        retention_policy=TraceRetentionPolicy(TraceLevel.SUMMARY),
    )
    world_nodes = {
        record.event_id: record.node_id
        for record in trace.records
        if isinstance(record, WorldEventTrace)
    }
    assert activated.header.event_id in world_nodes
    assert any(
        edge.source_node_id == world_nodes[trigger.header.event_id]
        and edge.target_node_id == world_nodes[activated.header.event_id]
        and edge.kind is TraceEdgeKind.CAUSED_EVENT
        for edge in trace.edges
    )


def test_retrieved_objective_extracts_when_the_lockdown_timer_has_not_fired() -> None:
    result = reduce_one_tick(_retrieved_extraction_state(False), FixedTickClock(TickRate.HZ_30))

    assert len(result.events) == 1
    assert isinstance(result.events[0], ObjectiveExtracted)
    assert result.state.objectives.entries[0].status is ObjectiveStatus.EXTRACTED


def test_mission_state_rejects_multiple_lockdown_timers() -> None:
    _, first_queue = MissionState().scheduled_events.schedule(1, ScheduledEventKind.LOCKDOWN)
    _, queue = first_queue.schedule(2, ScheduledEventKind.LOCKDOWN)

    with pytest.raises(ValueError, match="one pending or active lockdown"):
        MissionState(scheduled_events=queue)
