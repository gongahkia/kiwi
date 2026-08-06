from __future__ import annotations

from kiwi.domain.ids import EntityId, EventId, TraceNodeId
from kiwi.sim.events import EventKind
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    TraceConsequenceKind,
    TraceLevel,
    WorldEventTrace,
)
from kiwi.ui.timeline import TimelineEntryKind, mission_timeline


def test_mission_timeline_orders_retained_records_by_tick_then_node_id() -> None:
    trace = CausalTrace(
        b"t" * 32,
        TraceLevel.SUMMARY,
        (
            WorldEventTrace(TraceNodeId(1), 4, EventId(1), EventKind.FIRE_FIRED, "weapon fired"),
            ConsequenceTrace(
                TraceNodeId(2),
                1,
                TraceConsequenceKind.INJURY,
                (EntityId(1),),
                EventId(1),
                "operative injured",
            ),
        ),
        (),
    )

    timeline = mission_timeline(trace).select(TraceNodeId(1))

    assert tuple((entry.tick, entry.node_id.value, entry.kind) for entry in timeline.entries) == (
        (1, 2, TimelineEntryKind.CONSEQUENCE),
        (4, 1, TimelineEntryKind.WORLD_EVENT),
    )
    assert timeline.selected_node_id == TraceNodeId(1)
