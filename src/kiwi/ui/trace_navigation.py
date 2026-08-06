"""Headless navigation between retained trace nodes and archive-bound source."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.ids import EntityId, PolicyInvocationId, TraceNodeId
from kiwi.replay.source_archive import ReplaySourceArchive
from kiwi.trace.model import (
    CausalTrace,
    ExpressionEvaluationTrace,
    IntentionTrace,
    ObservationFactTrace,
    PolicyInvocationTrace,
    TraceEdge,
    TraceRecord,
    trace_record_id,
)
from kiwi.ui.historical_source import (
    HistoricalSourcePane,
    HistoricalSourceUnavailable,
    historical_source_pane,
)


class TraceNavigationUnavailableCode(StrEnum):
    NODE_NOT_RETAINED = "node_not_retained"
    SOURCE_NOT_RETAINED = "source_not_retained"
    EXPRESSION_NOT_SELECTED = "expression_not_selected"
    RELATED_EVENTS_NOT_RETAINED = "related_events_not_retained"


@dataclass(frozen=True, slots=True)
class TraceNavigationUnavailable:
    code: TraceNavigationUnavailableCode
    node_id: TraceNodeId | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.code, TraceNavigationUnavailableCode):
            raise TypeError("trace navigation unavailable result requires a code")
        if self.node_id is not None and not isinstance(self.node_id, TraceNodeId):
            raise TypeError("trace navigation unavailable node ID is invalid")


@dataclass(frozen=True, slots=True)
class SourceRelatedEvents:
    pane: HistoricalSourcePane
    origin_node_ids: tuple[TraceNodeId, ...]
    event_node_ids: tuple[TraceNodeId, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.pane, HistoricalSourcePane):
            raise TypeError("source related events require a historical source pane")
        _validate_node_ids(self.origin_node_ids, "source origin")
        if not isinstance(self.event_node_ids, tuple) or any(
            not isinstance(node_id, TraceNodeId) for node_id in self.event_node_ids
        ):
            raise TypeError("source related events must be immutable trace node IDs")
        if not self.event_node_ids or len(set(self.event_node_ids)) != len(self.event_node_ids):
            raise ValueError("source related events must be non-empty and unique")
        if any(node_id not in self.event_node_ids for node_id in self.origin_node_ids):
            raise ValueError("source related events must retain source origin nodes")


type TraceToSourceResult = HistoricalSourcePane | TraceNavigationUnavailable
type SourceToEventsResult = SourceRelatedEvents | TraceNavigationUnavailable


def trace_to_historical_source(
    trace: CausalTrace,
    archive: ReplaySourceArchive,
    node_id: TraceNodeId,
    *,
    eligible_entity_ids: tuple[EntityId, ...] | None = None,
) -> TraceToSourceResult:
    """Find the nearest retained archive-bound source reachable from one trace node."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("trace-to-source navigation requires a causal trace")
    if not isinstance(archive, ReplaySourceArchive):
        raise TypeError("trace-to-source navigation requires a replay source archive")
    if not isinstance(node_id, TraceNodeId):
        raise TypeError("trace-to-source navigation requires a trace node ID")
    if eligible_entity_ids is not None:
        _validate_entity_ids(eligible_entity_ids)
    records = {trace_record_id(record): record for record in trace.records}
    if node_id not in records:
        return TraceNavigationUnavailable(TraceNavigationUnavailableCode.NODE_NOT_RETAINED, node_id)
    invocation_entities = _invocation_entities(trace.records)
    distances = _ancestor_distances(trace.edges, node_id)
    for candidate_node_id, _ in sorted(
        distances.items(), key=lambda item: (item[1], item[0].value)
    ):
        pane = _source_pane_for_record(
            archive,
            records[candidate_node_id],
            invocation_entities,
        )
        if isinstance(pane, HistoricalSourcePane) and (
            eligible_entity_ids is None or pane.entity_id in eligible_entity_ids
        ):
            return pane
    return TraceNavigationUnavailable(TraceNavigationUnavailableCode.SOURCE_NOT_RETAINED, node_id)


def source_to_related_events(
    trace: CausalTrace,
    pane: HistoricalSourcePane,
) -> SourceToEventsResult:
    """Return retained causal descendants of one selected archived expression."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("source-to-event navigation requires a causal trace")
    if not isinstance(pane, HistoricalSourcePane):
        raise TypeError("source-to-event navigation requires a historical source pane")
    if pane.expression_id is None:
        return TraceNavigationUnavailable(TraceNavigationUnavailableCode.EXPRESSION_NOT_SELECTED)
    invocation_entities = _invocation_entities(trace.records)
    origin_node_ids = tuple(
        trace_record_id(record)
        for record in trace.records
        if _matches_pane(record, pane, invocation_entities)
    )
    if not origin_node_ids:
        return TraceNavigationUnavailable(
            TraceNavigationUnavailableCode.RELATED_EVENTS_NOT_RETAINED
        )
    records = {trace_record_id(record): record for record in trace.records}
    related_node_ids = _descendant_node_ids(trace.edges, origin_node_ids)
    return SourceRelatedEvents(
        pane,
        origin_node_ids,
        tuple(
            sorted(
                related_node_ids,
                key=lambda candidate_node_id: (
                    records[candidate_node_id].tick,
                    candidate_node_id.value,
                ),
            )
        ),
    )


def _source_pane_for_record(
    archive: ReplaySourceArchive,
    record: TraceRecord,
    invocation_entities: tuple[tuple[PolicyInvocationId, EntityId], ...],
) -> HistoricalSourcePane | HistoricalSourceUnavailable | None:
    if isinstance(record, PolicyInvocationTrace):
        return historical_source_pane(archive, record.entity_id)
    if isinstance(record, ExpressionEvaluationTrace):
        entity_id = _entity_for_invocation(invocation_entities, record.invocation_id)
        if entity_id is None:
            return None
        pane = historical_source_pane(archive, entity_id, record.expression_id)
        if isinstance(pane, HistoricalSourcePane) and record.source_span in pane.highlighted_spans:
            return pane
        return None
    if isinstance(record, IntentionTrace):
        pane = historical_source_pane(
            archive,
            record.origin.issuer_entity_id,
            record.origin.source_expression_id,
        )
        if (
            isinstance(pane, HistoricalSourcePane)
            and record.origin.source_span in pane.highlighted_spans
        ):
            return pane
    if isinstance(record, ObservationFactTrace):
        entity_id = _entity_for_invocation(invocation_entities, record.invocation_id)
        if entity_id is not None:
            return historical_source_pane(archive, entity_id)
    return None


def _matches_pane(
    record: TraceRecord,
    pane: HistoricalSourcePane,
    invocation_entities: tuple[tuple[PolicyInvocationId, EntityId], ...],
) -> bool:
    if isinstance(record, ExpressionEvaluationTrace):
        return (
            _entity_for_invocation(invocation_entities, record.invocation_id) == pane.entity_id
            and record.expression_id == pane.expression_id
            and record.source_span in pane.highlighted_spans
        )
    if isinstance(record, IntentionTrace):
        return (
            record.origin.issuer_entity_id == pane.entity_id
            and record.origin.source_expression_id == pane.expression_id
            and record.origin.source_span in pane.highlighted_spans
        )
    return False


def _invocation_entities(
    records: tuple[TraceRecord, ...],
) -> tuple[tuple[PolicyInvocationId, EntityId], ...]:
    pairs = tuple(
        (record.invocation_id, record.entity_id)
        for record in records
        if isinstance(record, PolicyInvocationTrace)
    )
    if len({invocation_id for invocation_id, _ in pairs}) != len(pairs):
        raise ValueError("causal trace retains duplicate policy invocation IDs")
    return pairs


def _entity_for_invocation(
    pairs: tuple[tuple[PolicyInvocationId, EntityId], ...],
    invocation_id: PolicyInvocationId,
) -> EntityId | None:
    for candidate_invocation_id, entity_id in pairs:
        if candidate_invocation_id == invocation_id:
            return entity_id
    return None


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
            if parent_node_id not in distances:
                distances[parent_node_id] = distances[node_id] + 1
                queue.append(parent_node_id)
    return distances


def _descendant_node_ids(
    edges: tuple[TraceEdge, ...],
    origin_node_ids: tuple[TraceNodeId, ...],
) -> tuple[TraceNodeId, ...]:
    outgoing: dict[TraceNodeId, list[TraceNodeId]] = {}
    for edge in edges:
        outgoing.setdefault(edge.source_node_id, []).append(edge.target_node_id)
    retained = set(origin_node_ids)
    queue = list(origin_node_ids)
    index = 0
    while index < len(queue):
        node_id = queue[index]
        index += 1
        for child_node_id in outgoing.get(node_id, ()):
            if child_node_id not in retained:
                retained.add(child_node_id)
                queue.append(child_node_id)
    return tuple(retained)


def _validate_node_ids(node_ids: tuple[TraceNodeId, ...], label: str) -> None:
    if not isinstance(node_ids, tuple) or any(
        not isinstance(node_id, TraceNodeId) for node_id in node_ids
    ):
        raise TypeError(f"{label} node IDs must be immutable trace node IDs")
    values = tuple(node_id.value for node_id in node_ids)
    if not node_ids or values != tuple(sorted(values)) or len(set(values)) != len(values):
        raise ValueError(f"{label} node IDs must be non-empty, unique, and node-ID ordered")


def _validate_entity_ids(entity_ids: tuple[EntityId, ...]) -> None:
    if not isinstance(entity_ids, tuple) or any(
        not isinstance(entity_id, EntityId) for entity_id in entity_ids
    ):
        raise TypeError("trace-to-source eligible entities must be immutable entity IDs")
    values = tuple(entity_id.value for entity_id in entity_ids)
    if values != tuple(sorted(values)) or len(set(values)) != len(values):
        raise ValueError("trace-to-source eligible entities must be unique and entity-ID ordered")
