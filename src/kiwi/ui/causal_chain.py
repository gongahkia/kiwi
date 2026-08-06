"""Immutable event-detail and causal-chain projections from retained trace data."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import TraceNodeId
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    ExpressionEvaluationTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    ObservationFactTrace,
    PolicyInvocationTrace,
    TraceEdge,
    TraceEdgeKind,
    TraceRecord,
    WorldEventTrace,
    trace_record_id,
)


class CausalPanelUnavailableCode(StrEnum):
    NODE_NOT_RETAINED = "node_not_retained"


class CausalNodeKind(StrEnum):
    POLICY = "policy"
    EXPRESSION = "expression"
    OBSERVATION = "observation"
    INTENTION = "intention"
    RESOLUTION = "resolution"
    WORLD_EVENT = "world_event"
    CONSEQUENCE = "consequence"


@dataclass(frozen=True, slots=True)
class CausalPanelUnavailable:
    code: CausalPanelUnavailableCode
    node_id: TraceNodeId

    def __post_init__(self) -> None:
        if not isinstance(self.code, CausalPanelUnavailableCode):
            raise TypeError("causal panel unavailable result requires a code")
        if not isinstance(self.node_id, TraceNodeId):
            raise TypeError("causal panel unavailable result requires a trace node ID")


@dataclass(frozen=True, slots=True)
class CausalNode:
    node_id: TraceNodeId
    tick: int
    kind: CausalNodeKind
    summary: str

    def __post_init__(self) -> None:
        if not isinstance(self.node_id, TraceNodeId):
            raise TypeError("causal node requires a trace node ID")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool) or self.tick < 0:
            raise ValueError("causal node tick must be non-negative")
        if not isinstance(self.kind, CausalNodeKind):
            raise TypeError("causal node requires a node kind")
        if not isinstance(self.summary, str) or not self.summary:
            raise ValueError("causal node summary must be non-empty")


@dataclass(frozen=True, slots=True)
class CausalField:
    label: str
    value: str

    def __post_init__(self) -> None:
        if not isinstance(self.label, str) or not self.label:
            raise ValueError("causal detail field label must be non-empty")
        if not isinstance(self.value, str) or not self.value:
            raise ValueError("causal detail field value must be non-empty")


@dataclass(frozen=True, slots=True)
class CausalLink:
    edge_id: int
    source_node_id: TraceNodeId
    target_node_id: TraceNodeId
    kind: TraceEdgeKind

    def __post_init__(self) -> None:
        if not isinstance(self.edge_id, int) or isinstance(self.edge_id, bool) or self.edge_id <= 0:
            raise ValueError("causal link edge ID must be positive")
        if not isinstance(self.source_node_id, TraceNodeId) or not isinstance(
            self.target_node_id, TraceNodeId
        ):
            raise TypeError("causal link requires trace node IDs")
        if not isinstance(self.kind, TraceEdgeKind):
            raise TypeError("causal link requires a trace edge kind")


@dataclass(frozen=True, slots=True)
class EventDetail:
    event: CausalNode
    fields: tuple[CausalField, ...]
    parent_links: tuple[CausalLink, ...]
    child_links: tuple[CausalLink, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.event, CausalNode):
            raise TypeError("event detail requires a causal node")
        _validate_fields(self.fields)
        _validate_links(self.parent_links, "parent")
        _validate_links(self.child_links, "child")
        if any(link.target_node_id != self.event.node_id for link in self.parent_links):
            raise ValueError("event detail parent links must target its event")
        if any(link.source_node_id != self.event.node_id for link in self.child_links):
            raise ValueError("event detail child links must start at its event")


@dataclass(frozen=True, slots=True)
class CausalChainNode:
    node: CausalNode
    distance: int

    def __post_init__(self) -> None:
        if not isinstance(self.node, CausalNode):
            raise TypeError("causal chain node requires a causal node")
        if (
            not isinstance(self.distance, int)
            or isinstance(self.distance, bool)
            or self.distance < 1
        ):
            raise ValueError("causal chain node distance must be positive")


@dataclass(frozen=True, slots=True)
class CausalChainPanel:
    detail: EventDetail
    ancestors: tuple[CausalChainNode, ...]
    links: tuple[CausalLink, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.detail, EventDetail):
            raise TypeError("causal chain panel requires event detail")
        if not isinstance(self.ancestors, tuple) or any(
            not isinstance(ancestor, CausalChainNode) for ancestor in self.ancestors
        ):
            raise TypeError("causal chain panel ancestors must be immutable causal chain nodes")
        keys = tuple(
            (ancestor.distance, ancestor.node.node_id.value) for ancestor in self.ancestors
        )
        if keys != tuple(sorted(keys)) or len(
            {ancestor.node.node_id for ancestor in self.ancestors}
        ) != len(self.ancestors):
            raise ValueError("causal chain ancestors must be unique and canonically ordered")
        _validate_links(self.links, "chain")
        node_ids = {
            self.detail.event.node_id,
            *(ancestor.node.node_id for ancestor in self.ancestors),
        }
        if any(
            link.source_node_id not in node_ids or link.target_node_id not in node_ids
            for link in self.links
        ):
            raise ValueError("causal chain links must stay inside its retained nodes")


type CausalChainPanelResult = CausalChainPanel | CausalPanelUnavailable


def causal_chain_panel(
    trace: CausalTrace,
    node_id: TraceNodeId,
) -> CausalChainPanelResult:
    """Project one retained trace node and all retained causal ancestors."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("causal chain panel requires a causal trace")
    if not isinstance(node_id, TraceNodeId):
        raise TypeError("causal chain panel requires a trace node ID")
    records = {trace_record_id(record): record for record in trace.records}
    selected = records.get(node_id)
    if selected is None:
        return CausalPanelUnavailable(CausalPanelUnavailableCode.NODE_NOT_RETAINED, node_id)
    detail = EventDetail(
        _causal_node(selected),
        _detail_fields(selected),
        tuple(_causal_link(edge) for edge in trace.edges if edge.target_node_id == node_id),
        tuple(_causal_link(edge) for edge in trace.edges if edge.source_node_id == node_id),
    )
    distances = _ancestor_distances(trace.edges, node_id)
    ancestors = tuple(
        CausalChainNode(_causal_node(records[ancestor_id]), distance)
        for ancestor_id, distance in sorted(
            distances.items(), key=lambda item: (item[1], item[0].value)
        )
    )
    node_ids = {node_id, *distances}
    links = tuple(
        _causal_link(edge)
        for edge in trace.edges
        if edge.source_node_id in node_ids and edge.target_node_id in node_ids
    )
    return CausalChainPanel(detail, ancestors, links)


def _ancestor_distances(
    edges: tuple[TraceEdge, ...],
    selected_node_id: TraceNodeId,
) -> dict[TraceNodeId, int]:
    incoming: dict[TraceNodeId, list[TraceNodeId]] = {}
    for edge in edges:
        incoming.setdefault(edge.target_node_id, []).append(edge.source_node_id)
    distances = {selected_node_id: 0}
    queue = [selected_node_id]
    index = 0
    while index < len(queue):
        node_id = queue[index]
        index += 1
        for parent_node_id in incoming.get(node_id, ()):
            if parent_node_id in distances:
                continue
            distances[parent_node_id] = distances[node_id] + 1
            queue.append(parent_node_id)
    del distances[selected_node_id]
    return distances


def _causal_node(record: TraceRecord) -> CausalNode:
    node_id = trace_record_id(record)
    if isinstance(record, PolicyInvocationTrace):
        return CausalNode(node_id, record.tick, CausalNodeKind.POLICY, record.result_summary)
    if isinstance(record, ExpressionEvaluationTrace):
        return CausalNode(node_id, record.tick, CausalNodeKind.EXPRESSION, record.value_summary)
    if isinstance(record, ObservationFactTrace):
        return CausalNode(
            node_id,
            record.tick,
            CausalNodeKind.OBSERVATION,
            f"{'.'.join(record.path)}: {record.value_summary}",
        )
    if isinstance(record, IntentionTrace):
        return CausalNode(node_id, record.tick, CausalNodeKind.INTENTION, record.origin.kind.value)
    if isinstance(record, IntentionResolutionTrace):
        reason = f" ({record.reason_code})" if record.reason_code is not None else ""
        return CausalNode(
            node_id,
            record.tick,
            CausalNodeKind.RESOLUTION,
            f"{record.status.value}{reason}",
        )
    if isinstance(record, WorldEventTrace):
        return CausalNode(node_id, record.tick, CausalNodeKind.WORLD_EVENT, record.summary)
    if isinstance(record, ConsequenceTrace):
        return CausalNode(node_id, record.tick, CausalNodeKind.CONSEQUENCE, record.summary)
    raise AssertionError("unsupported retained trace record")


def _detail_fields(record: TraceRecord) -> tuple[CausalField, ...]:
    if isinstance(record, PolicyInvocationTrace):
        return (
            CausalField("entity", str(record.entity_id.value)),
            CausalField("invocation", str(record.invocation_id.value)),
        )
    if isinstance(record, ExpressionEvaluationTrace):
        return (
            CausalField("invocation", str(record.invocation_id.value)),
            CausalField("expression", str(record.expression_id.value)),
        )
    if isinstance(record, ObservationFactTrace):
        return (
            CausalField("invocation", str(record.invocation_id.value)),
            CausalField("field", ".".join(record.path)),
        )
    if isinstance(record, IntentionTrace):
        return (
            CausalField("intention", str(record.origin.intention_id.value)),
            CausalField("issuer", str(record.origin.issuer_entity_id.value)),
        )
    if isinstance(record, IntentionResolutionTrace):
        fields = [
            CausalField("intention", str(record.intention_id.value)),
            CausalField("status", record.status.value),
        ]
        if record.reason_code is not None:
            fields.append(CausalField("reason", record.reason_code))
        return tuple(fields)
    if isinstance(record, WorldEventTrace):
        return (
            CausalField("event", str(record.event_id.value)),
            CausalField("kind", record.event_kind.value),
        )
    if isinstance(record, ConsequenceTrace):
        return (
            CausalField("event", str(record.event_id.value)),
            CausalField("kind", record.kind.value),
            CausalField(
                "subjects",
                ",".join(str(entity_id.value) for entity_id in record.subject_entity_ids) or "none",
            ),
        )
    raise AssertionError("unsupported retained trace record")


def _causal_link(edge: TraceEdge) -> CausalLink:
    return CausalLink(
        edge.edge_id.value,
        edge.source_node_id,
        edge.target_node_id,
        edge.kind,
    )


def _validate_fields(fields: tuple[CausalField, ...]) -> None:
    if (
        not isinstance(fields, tuple)
        or not fields
        or any(not isinstance(field, CausalField) for field in fields)
    ):
        raise TypeError("event detail fields must be a non-empty tuple of causal fields")
    labels = tuple(field.label for field in fields)
    if len(set(labels)) != len(labels):
        raise ValueError("event detail fields must have unique labels")


def _validate_links(links: tuple[CausalLink, ...], label: str) -> None:
    if not isinstance(links, tuple) or any(not isinstance(link, CausalLink) for link in links):
        raise TypeError(f"causal {label} links must be a tuple of causal links")
    edge_ids = tuple(link.edge_id for link in links)
    if edge_ids != tuple(sorted(edge_ids)) or len(set(edge_ids)) != len(edge_ids):
        raise ValueError(f"causal {label} links must be unique and edge-ID ordered")
