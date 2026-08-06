from __future__ import annotations

from dataclasses import replace

import pytest

from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import EntityId
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.events import ObjectiveExtracted, ObjectiveRetrieved
from kiwi.sim.hashing import decode_canonical_state, encode_canonical_state, hash_canonical_state
from kiwi.sim.objectives import ObjectiveStatus, ObjectiveStore, RetrievalObjective
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.runner import HeadlessRun
from kiwi.sim.snapshot import PresentationPoint, build_presentation_snapshot
from kiwi.sim.state import MissionPhase, MissionState, add_entity
from kiwi.trace.capture import capture_run_trace
from kiwi.trace.model import TraceEdgeKind, WorldEventTrace


def _position(x: int, y: int) -> WorldPosition:
    return WorldPosition(WorldSubunits(x), WorldSubunits(y))


def _rectangle(minimum_x: int, minimum_y: int, maximum_x: int, maximum_y: int) -> WorldRectangle:
    return WorldRectangle(
        WorldSubunits(minimum_x),
        WorldSubunits(minimum_y),
        WorldSubunits(maximum_x),
        WorldSubunits(maximum_y),
    )


def _active_objective_state() -> MissionState:
    state, first = add_entity(MissionState(phase=MissionPhase.ACTIVE), _position(10, 10))
    state, second = add_entity(state, _position(-100, -100))
    objective_id, allocator = state.id_allocator.allocate_objective()
    return replace(
        state,
        id_allocator=allocator,
        objectives=ObjectiveStore(
            (
                RetrievalObjective(
                    objective_id,
                    _rectangle(0, 0, 100, 100),
                    _rectangle(1_000, 1_000, 1_100, 1_100),
                    (first.entity_id, second.entity_id),
                ),
            )
        ),
    )


def test_objective_retrieval_then_full_squad_extraction_is_causal_and_replayable() -> None:
    clock = FixedTickClock(TickRate.HZ_30)
    initial = _active_objective_state()

    retrieved = reduce_one_tick(initial, clock)

    assert isinstance(retrieved.events, tuple)
    assert len(retrieved.events) == 1
    assert isinstance(retrieved.events[0], ObjectiveRetrieved)
    retrieval_event = retrieved.events[0]
    assert retrieval_event.objective.status is ObjectiveStatus.RETRIEVED
    assert retrieval_event.objective.retrieved_by == retrieved.state.entities[0].entity_id
    assert build_presentation_snapshot(retrieved.state).objective_marker == PresentationPoint(
        1_050.0, 1_050.0, 0
    )
    assert decode_canonical_state(encode_canonical_state(retrieved.state)) == retrieved.state

    extracted_input = replace(
        retrieved.state,
        entities=tuple(
            replace(entity, position=_position(1_050, 1_050)) for entity in retrieved.state.entities
        ),
    )
    extracted = reduce_one_tick(extracted_input, clock)

    assert len(extracted.events) == 1
    assert isinstance(extracted.events[0], ObjectiveExtracted)
    extraction_event = extracted.events[0]
    assert extraction_event.objective.status is ObjectiveStatus.EXTRACTED
    assert extraction_event.header.parent_event_ids == (retrieval_event.header.event_id,)
    assert build_presentation_snapshot(extracted.state).objective_marker is None
    assert hash_canonical_state(extracted.state) != hash_canonical_state(retrieved.state)
    trace = capture_run_trace(
        HeadlessRun(extracted.state, retrieved.events + extracted.events),
        hash_canonical_state(extracted.state),
    )
    world_nodes = {
        record.event_id: record.node_id
        for record in trace.records
        if isinstance(record, WorldEventTrace)
    }
    assert any(
        edge.source_node_id == world_nodes[retrieval_event.header.event_id]
        and edge.target_node_id == world_nodes[extraction_event.header.event_id]
        and edge.kind is TraceEdgeKind.CAUSED_EVENT
        for edge in trace.edges
    )


def test_objective_store_rejects_unallocated_or_unknown_entities() -> None:
    objective_id, allocator = MissionState().id_allocator.allocate_objective()
    objective = RetrievalObjective(
        objective_id,
        _rectangle(0, 0, 100, 100),
        _rectangle(1_000, 1_000, 1_100, 1_100),
        (EntityId(1),),
    )

    with pytest.raises(ValueError, match="objective entities"):
        MissionState(id_allocator=allocator, objectives=ObjectiveStore((objective,)))
