from __future__ import annotations

from dataclasses import replace

from kiwi.domain.ids import EntityId, EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.trace.model import (
    CausalTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    TraceResolutionStatus,
    WorldEventTrace,
)
from kiwi.trace.queries import (
    IntentionFailureExplanation,
    IntentionRejectionExplanation,
    IntentionSelectionExplanation,
    TraceQueryUnavailable,
    TraceQueryUnavailableCode,
    why_failed,
    why_not_selected,
    why_selected,
)


def test_queries_return_retained_selection_rejection_and_failure_evidence() -> None:
    trace = _trace()

    selected = why_selected(trace, IntentionId(1))
    rejected = why_not_selected(trace, IntentionId(2))
    failed = why_failed(trace, IntentionId(1))

    assert isinstance(selected, IntentionSelectionExplanation)
    assert selected.origin.source_span.file_id == SourceFileId("trace-queries.dtr")
    assert selected.resolution.status is TraceResolutionStatus.SELECTED
    assert isinstance(rejected, IntentionRejectionExplanation)
    assert rejected.resolution.reason_code == "action_channel_occupied"
    assert rejected.resolution.competing_intention_ids == (IntentionId(1),)
    assert isinstance(failed, IntentionFailureExplanation)
    assert failed.failure_event.event_kind is EventKind.FIRE_REJECTED
    assert failed.path_node_ids == (TraceNodeId(2), TraceNodeId(3), TraceNodeId(4))


def test_queries_report_unavailable_without_retained_evidence() -> None:
    trace = _trace()
    no_failure = CausalTrace(
        trace.run_state_hash,
        trace.level,
        tuple(
            replace(record, event_kind=EventKind.FIRE_FIRED)
            if isinstance(record, WorldEventTrace) and record.event_kind is EventKind.FIRE_REJECTED
            else record
            for record in trace.records
        ),
        trace.edges,
    )

    selected = why_selected(trace, IntentionId(99))
    not_selected = why_not_selected(trace, IntentionId(1))
    failed_rejection = why_failed(trace, IntentionId(2))
    failed_without_event = why_failed(no_failure, IntentionId(1))

    assert isinstance(selected, TraceQueryUnavailable)
    assert selected.code is TraceQueryUnavailableCode.INTENTION_NOT_RETAINED
    assert isinstance(not_selected, TraceQueryUnavailable)
    assert not_selected.code is TraceQueryUnavailableCode.INTENTION_NOT_REJECTED
    assert isinstance(failed_rejection, TraceQueryUnavailable)
    assert failed_rejection.code is TraceQueryUnavailableCode.INTENTION_NOT_SELECTED
    assert isinstance(failed_without_event, TraceQueryUnavailable)
    assert failed_without_event.code is TraceQueryUnavailableCode.FAILURE_NOT_RETAINED


def _trace() -> CausalTrace:
    source = SourceFile(SourceFileId("trace-queries.dtr"), "x")
    span = source.span(ByteOffset(0), ByteOffset(1))
    selected_origin = IntentionOrigin(
        IntentionId(1),
        EntityId(1),
        PolicyInvocationId(1),
        ExpressionId(1),
        span,
        0,
        3,
        IntentionKind.FIRE,
    )
    rejected_origin = IntentionOrigin(
        IntentionId(2),
        EntityId(1),
        PolicyInvocationId(1),
        ExpressionId(2),
        span,
        1,
        3,
        IntentionKind.MOVE_TOWARD,
    )
    records = (
        IntentionTrace(TraceNodeId(1), 3, selected_origin),
        IntentionResolutionTrace(
            TraceNodeId(2),
            3,
            IntentionId(1),
            TraceResolutionStatus.SELECTED,
            None,
            (),
            (EventId(1),),
        ),
        WorldEventTrace(
            TraceNodeId(3),
            3,
            EventId(1),
            EventKind.INTENTION_SELECTED,
            "intention selected",
        ),
        WorldEventTrace(TraceNodeId(4), 3, EventId(2), EventKind.FIRE_REJECTED, "fire rejected"),
        IntentionTrace(TraceNodeId(5), 3, rejected_origin),
        IntentionResolutionTrace(
            TraceNodeId(6),
            3,
            IntentionId(2),
            TraceResolutionStatus.REJECTED,
            "action_channel_occupied",
            (IntentionId(1),),
            (EventId(3),),
        ),
    )
    edges = (
        TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.VALIDATED_BY),
        TraceEdge(TraceEdgeId(2), TraceNodeId(2), TraceNodeId(3), TraceEdgeKind.CAUSED_EVENT),
        TraceEdge(TraceEdgeId(3), TraceNodeId(3), TraceNodeId(4), TraceEdgeKind.CAUSED_EVENT),
        TraceEdge(TraceEdgeId(4), TraceNodeId(5), TraceNodeId(6), TraceEdgeKind.REJECTED_BECAUSE),
        TraceEdge(TraceEdgeId(5), TraceNodeId(1), TraceNodeId(6), TraceEdgeKind.SELECTED_OVER),
    )
    return CausalTrace(b"q" * 32, TraceLevel.FULL, records, edges)
