from __future__ import annotations

from collections.abc import Callable

import pytest

from kiwi.domain.ids import EntityId, EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.ids import ExpressionId, FunctionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    ExpressionEvaluationTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    ObservationFactTrace,
    PolicyInvocationTrace,
    TraceConsequenceKind,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    TraceResolutionStatus,
    WorldEventTrace,
)
from kiwi.trace.retention import TraceRetentionPolicy, retain_trace


def test_trace_retention_levels_filter_detail_deterministically() -> None:
    trace = _trace()

    summary = retain_trace(trace, TraceRetentionPolicy(TraceLevel.SUMMARY))
    decision = retain_trace(trace, TraceRetentionPolicy(TraceLevel.DECISION))
    full = retain_trace(trace, TraceRetentionPolicy(TraceLevel.FULL))

    assert summary.level is TraceLevel.SUMMARY
    assert tuple(record.node_id.value for record in summary.records) == (1, 4, 5, 7, 8)
    assert tuple(edge.edge_id.value for edge in summary.edges) == (2, 4)
    assert decision.level is TraceLevel.DECISION
    assert tuple(record.node_id.value for record in decision.records) == (1, 3, 4, 5, 6, 7, 8)
    assert tuple(record.node_id.value for record in full.records) == tuple(range(1, 9))


def test_trace_retention_prefers_consequence_chain_with_time_record_and_edge_limits() -> None:
    trace = _trace()

    trailing = retain_trace(
        trace,
        TraceRetentionPolicy(TraceLevel.FULL, retained_ticks=1),
    )
    bounded = retain_trace(
        trace,
        TraceRetentionPolicy(TraceLevel.FULL, max_records=4, max_edges=1),
    )

    assert tuple(record.node_id.value for record in trailing.records) == (7, 8)
    assert tuple(edge.edge_id.value for edge in trailing.edges) == (4,)
    assert tuple(record.node_id.value for record in bounded.records) == (4, 5, 7, 8)
    assert tuple(edge.edge_id.value for edge in bounded.edges) == (4,)


@pytest.mark.parametrize(
    "factory",
    (
        lambda: TraceRetentionPolicy(retained_ticks=0),
        lambda: TraceRetentionPolicy(max_records=0),
        lambda: TraceRetentionPolicy(max_edges=0),
    ),
)
def test_trace_retention_rejects_empty_limits(factory: Callable[[], TraceRetentionPolicy]) -> None:
    with pytest.raises(ValueError):
        factory()


def _trace() -> CausalTrace:
    source = SourceFile(SourceFileId("trace-retention.dtr"), "x")
    span = source.span(ByteOffset(0), ByteOffset(1))
    origin = IntentionOrigin(
        IntentionId(1),
        EntityId(1),
        PolicyInvocationId(1),
        ExpressionId(1),
        span,
        0,
        3,
        IntentionKind.FIRE,
    )
    records = (
        PolicyInvocationTrace(
            TraceNodeId(1),
            3,
            EntityId(1),
            PolicyInvocationId(1),
            b"p" * 32,
            FunctionId(0),
            b"m" * 32,
            "success",
        ),
        ExpressionEvaluationTrace(
            TraceNodeId(2), 3, PolicyInvocationId(1), ExpressionId(1), span, "Fire request"
        ),
        ObservationFactTrace(
            TraceNodeId(3),
            3,
            PolicyInvocationId(1),
            ("nearest_contact",),
            "contact",
            (EventId(1),),
        ),
        IntentionTrace(TraceNodeId(4), 3, origin),
        IntentionResolutionTrace(
            TraceNodeId(5),
            3,
            IntentionId(1),
            TraceResolutionStatus.SELECTED,
            None,
            (),
            (EventId(2),),
        ),
        WorldEventTrace(
            TraceNodeId(6), 3, EventId(1), EventKind.PROJECTILE_ADVANCED, "projectile advanced"
        ),
        WorldEventTrace(TraceNodeId(7), 4, EventId(2), EventKind.INJURY_CHANGED, "injury changed"),
        ConsequenceTrace(
            TraceNodeId(8),
            4,
            TraceConsequenceKind.INJURY,
            (EntityId(1),),
            EventId(2),
            "operative injured",
        ),
    )
    edges = (
        TraceEdge(TraceEdgeId(1), TraceNodeId(2), TraceNodeId(4), TraceEdgeKind.COMPUTED_FROM),
        TraceEdge(TraceEdgeId(2), TraceNodeId(4), TraceNodeId(5), TraceEdgeKind.VALIDATED_BY),
        TraceEdge(TraceEdgeId(3), TraceNodeId(6), TraceNodeId(7), TraceEdgeKind.CAUSED_EVENT),
        TraceEdge(TraceEdgeId(4), TraceNodeId(7), TraceNodeId(8), TraceEdgeKind.CONTRIBUTED_TO),
    )
    return CausalTrace(b"r" * 32, TraceLevel.FULL, records, edges)
