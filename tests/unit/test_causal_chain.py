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
from kiwi.ui.causal_chain import (
    CausalChainPanel,
    CausalPanelUnavailable,
    CausalPanelUnavailableCode,
    causal_chain_panel,
)


def test_causal_chain_panel_projects_detail_and_retained_ancestors() -> None:
    trace = _trace()

    result = causal_chain_panel(trace, TraceNodeId(3))

    assert isinstance(result, CausalChainPanel)
    assert result.detail.event.summary == "operative injured"
    assert result.detail.fields[-1].value == "1"
    assert tuple(
        (ancestor.distance, ancestor.node.node_id.value) for ancestor in result.ancestors
    ) == ((1, 2), (2, 1))
    assert tuple(link.edge_id for link in result.links) == (1, 2)
    assert tuple(link.edge_id for link in result.detail.parent_links) == (2,)


def test_causal_chain_panel_reports_missing_retained_node() -> None:
    result = causal_chain_panel(_trace(), TraceNodeId(99))

    assert isinstance(result, CausalPanelUnavailable)
    assert result.code is CausalPanelUnavailableCode.NODE_NOT_RETAINED


def test_causal_chain_panel_represents_retained_consequence_without_subjects() -> None:
    trace = CausalTrace(
        b"e" * 32,
        TraceLevel.SUMMARY,
        (
            ConsequenceTrace(
                TraceNodeId(1),
                0,
                TraceConsequenceKind.SYSTEM_FAULT,
                (),
                EventId(1),
                "system fault",
            ),
        ),
        (),
    )

    result = causal_chain_panel(trace, TraceNodeId(1))

    assert isinstance(result, CausalChainPanel)
    assert result.detail.fields[-1].value == "none"


def _trace() -> CausalTrace:
    return CausalTrace(
        b"c" * 32,
        TraceLevel.SUMMARY,
        (
            WorldEventTrace(TraceNodeId(1), 2, EventId(1), EventKind.FIRE_FIRED, "weapon fired"),
            WorldEventTrace(
                TraceNodeId(2),
                3,
                EventId(2),
                EventKind.PROJECTILE_IMPACTED,
                "projectile impacted",
            ),
            ConsequenceTrace(
                TraceNodeId(3),
                3,
                TraceConsequenceKind.INJURY,
                (EntityId(1),),
                EventId(2),
                "operative injured",
            ),
        ),
        (
            TraceEdge(TraceEdgeId(1), TraceNodeId(1), TraceNodeId(2), TraceEdgeKind.CAUSED_EVENT),
            TraceEdge(
                TraceEdgeId(2),
                TraceNodeId(2),
                TraceNodeId(3),
                TraceEdgeKind.CONTRIBUTED_TO,
            ),
        ),
    )
