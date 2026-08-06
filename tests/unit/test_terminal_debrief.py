from __future__ import annotations

from kiwi.domain.ids import EntityId, EventId, TraceNodeId
from kiwi.sim.events import EventKind
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    TraceConsequenceKind,
    TraceEdge,
    TraceEdgeId,
    TraceEdgeKind,
    TraceLevel,
    WorldEventTrace,
)
from kiwi.ui.terminal_debrief import (
    TerminalDebrief,
    TerminalDebriefUnavailable,
    TerminalDebriefUnavailableCode,
    terminal_debrief,
)


def test_terminal_debrief_selects_each_retained_injury_with_its_causal_chain() -> None:
    trace = _trace()
    result = terminal_debrief(trace)

    assert isinstance(result, TerminalDebrief)
    assert tuple(injury.node_id.value for injury in result.injuries) == (2, 3)
    assert result.selected_node_id == TraceNodeId(2)
    selected = result.select_injury(trace, TraceNodeId(3))
    assert isinstance(selected, TerminalDebrief)
    assert selected.chain.detail.event.node_id == TraceNodeId(3)
    assert selected.chain.ancestors[0].node.node_id == TraceNodeId(1)


def test_terminal_debrief_reports_missing_injury_consequence() -> None:
    result = terminal_debrief(CausalTrace(b"d" * 32, TraceLevel.SUMMARY, (), ()))

    assert isinstance(result, TerminalDebriefUnavailable)
    assert result.code is TerminalDebriefUnavailableCode.NO_INJURY_RETAINED


def test_terminal_debrief_rejects_an_injury_not_retained_by_its_trace() -> None:
    result = terminal_debrief(_trace())

    assert isinstance(result, TerminalDebrief)
    selected = result.select_injury(
        CausalTrace(b"e" * 32, TraceLevel.SUMMARY, (), ()), TraceNodeId(2)
    )

    assert isinstance(selected, TerminalDebriefUnavailable)
    assert selected.code is TerminalDebriefUnavailableCode.INJURY_NOT_RETAINED


def _trace() -> CausalTrace:
    return CausalTrace(
        b"d" * 32,
        TraceLevel.SUMMARY,
        (
            WorldEventTrace(TraceNodeId(1), 2, EventId(1), EventKind.DAMAGE_APPLIED, "damage"),
            ConsequenceTrace(
                TraceNodeId(2),
                2,
                TraceConsequenceKind.INJURY,
                (EntityId(1),),
                EventId(1),
                "first injury",
            ),
            ConsequenceTrace(
                TraceNodeId(3),
                3,
                TraceConsequenceKind.INJURY,
                (EntityId(2),),
                EventId(2),
                "second injury",
            ),
        ),
        (
            TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.CONTRIBUTED_TO),
            TraceEdge(TraceEdgeId(2), TraceNodeId(1), TraceNodeId(3), TraceEdgeKind.CONTRIBUTED_TO),
        ),
    )
