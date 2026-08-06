from __future__ import annotations

from kiwi.domain.ids import EntityId, EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.source import SourceFileId
from kiwi.replay.source_archive import (
    HistoricalPolicySource,
    HistoricalSourceFile,
    ReplaySourceArchive,
)
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.sim.policy_versions import PolicyVersion
from kiwi.trace.model import (
    CausalTrace,
    ExpressionEvaluationTrace,
    IntentionTrace,
    PolicyInvocationTrace,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    WorldEventTrace,
)
from kiwi.ui.compile_output import compile_editor_source
from kiwi.ui.editor import EditorState
from kiwi.ui.historical_source import HistoricalSourcePane
from kiwi.ui.trace_navigation import (
    SourceRelatedEvents,
    TraceNavigationUnavailable,
    TraceNavigationUnavailableCode,
    source_to_related_events,
    trace_to_historical_source,
)


def test_trace_and_source_navigation_follow_retained_causal_edges() -> None:
    archive, trace = _archive_and_trace()

    pane = trace_to_historical_source(trace, archive, TraceNodeId(4))

    assert isinstance(pane, HistoricalSourcePane)
    assert pane.expression_id is not None
    related = source_to_related_events(trace, pane)
    assert isinstance(related, SourceRelatedEvents)
    assert related.origin_node_ids == (TraceNodeId(2), TraceNodeId(3))
    assert related.event_node_ids == (TraceNodeId(2), TraceNodeId(3), TraceNodeId(4))


def test_trace_navigation_reports_absent_trace_or_unselected_source() -> None:
    archive, trace = _archive_and_trace()
    pane = trace_to_historical_source(trace, archive, TraceNodeId(1))
    assert isinstance(pane, HistoricalSourcePane)

    missing_trace = trace_to_historical_source(trace, archive, TraceNodeId(99))
    no_expression = source_to_related_events(
        trace,
        HistoricalSourcePane(
            pane.entity_id,
            pane.policy_version,
            pane.source,
            None,
            (),
        ),
    )

    assert isinstance(missing_trace, TraceNavigationUnavailable)
    assert missing_trace.code is TraceNavigationUnavailableCode.NODE_NOT_RETAINED
    assert isinstance(no_expression, TraceNavigationUnavailable)
    assert no_expression.code is TraceNavigationUnavailableCode.EXPRESSION_NOT_SELECTED


def _archive_and_trace() -> tuple[ReplaySourceArchive, CausalTrace]:
    output = compile_editor_source(
        SourceFileId("navigation.dtr"),
        EditorState.from_text("fn choose(value: Int) -> Int = value"),
    )
    assert output.artifact is not None
    bytecode = output.artifact.bytecode
    expression = bytecode.source_map.entries[0]
    policy = HistoricalPolicySource(
        EntityId(1),
        PolicyVersion.from_bytecode(bytecode, FunctionId(0)),
        FunctionId(0),
        bytecode,
    )
    archive = ReplaySourceArchive(
        b"n" * 32,
        (HistoricalSourceFile(output.source, bytecode.header.source_language_version),),
        (policy,),
    )
    origin = IntentionOrigin(
        IntentionId(1),
        EntityId(1),
        PolicyInvocationId(1),
        expression.expression_id,
        expression.span,
        0,
        0,
        IntentionKind.FIRE,
    )
    trace = CausalTrace(
        b"t" * 32,
        TraceLevel.FULL,
        (
            PolicyInvocationTrace(
                TraceNodeId(1),
                0,
                EntityId(1),
                PolicyInvocationId(1),
                b"p" * 32,
                FunctionId(0),
                b"m" * 32,
                "success",
            ),
            ExpressionEvaluationTrace(
                TraceNodeId(2),
                0,
                PolicyInvocationId(1),
                expression.expression_id,
                expression.span,
                "value",
            ),
            IntentionTrace(TraceNodeId(3), 0, origin),
            WorldEventTrace(
                TraceNodeId(4),
                1,
                EventId(1),
                EventKind.FIRE_FIRED,
                "weapon fired",
            ),
        ),
        (
            TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.COMPUTED_FROM),
            TraceEdge(TraceEdgeId(2), TraceNodeId(2), TraceNodeId(3), TraceEdgeKind.CONSTRUCTED),
            TraceEdge(TraceEdgeId(3), TraceNodeId(3), TraceNodeId(4), TraceEdgeKind.CAUSED_EVENT),
        ),
    )
    return archive, trace
