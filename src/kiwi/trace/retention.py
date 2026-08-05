"""Deterministic detail filtering and bounded retention for causal traces."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.ids import EventId, TraceNodeId
from kiwi.sim.events import EventKind
from kiwi.trace.model import (
    MAX_TRACE_EDGES,
    MAX_TRACE_RECORDS,
    CausalTrace,
    ConsequenceTrace,
    ExpressionEvaluationTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    ObservationFactTrace,
    PolicyInvocationTrace,
    TraceEdge,
    TraceEdgeKind,
    TraceLevel,
    TraceRecord,
    WorldEventTrace,
    trace_record_id,
)

_SUMMARY_WORLD_EVENT_KINDS = frozenset(
    {
        EventKind.MISSION_STARTED,
        EventKind.ABORT_REQUESTED,
        EventKind.SIGNAL_ISSUED,
        EventKind.SCHEDULED_TRIGGER_FIRED,
        EventKind.COMMAND_REJECTED,
        EventKind.INTENTION_SELECTED,
        EventKind.INTENTION_REJECTED,
        EventKind.COVER_RESERVATION_GRANTED,
        EventKind.COVER_RESERVATION_REJECTED,
        EventKind.MOVEMENT_ROUTE_REJECTED,
        EventKind.MOVEMENT_BLOCKED,
        EventKind.MOVEMENT_ARRIVED,
        EventKind.FIRE_FIRED,
        EventKind.FIRE_REJECTED,
        EventKind.PROJECTILE_IMPACTED,
        EventKind.DAMAGE_APPLIED,
        EventKind.INJURY_CHANGED,
        EventKind.SUPPRESSION_CHANGED,
    }
)


@dataclass(frozen=True, slots=True)
class TraceRetentionPolicy:
    """One non-authoritative trace detail level and bounded retention budget."""

    level: TraceLevel = TraceLevel.DECISION
    retained_ticks: int | None = None
    max_records: int = MAX_TRACE_RECORDS
    max_edges: int = MAX_TRACE_EDGES

    def __post_init__(self) -> None:
        if not isinstance(self.level, TraceLevel):
            raise ValueError("trace retention policy requires a trace level")
        if self.retained_ticks is not None and (
            not isinstance(self.retained_ticks, int)
            or isinstance(self.retained_ticks, bool)
            or self.retained_ticks <= 0
        ):
            raise ValueError("trace retained ticks must be a positive integer or None")
        _limit(self.max_records, MAX_TRACE_RECORDS, "trace record")
        _limit(self.max_edges, MAX_TRACE_EDGES, "trace edge")


def retain_trace(trace: CausalTrace, policy: TraceRetentionPolicy) -> CausalTrace:
    """Return a deterministic retained graph with no dangling edges."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("trace retention requires a causal trace")
    if not isinstance(policy, TraceRetentionPolicy):
        raise TypeError("trace retention requires a trace retention policy")
    return build_retained_trace(trace.run_state_hash, trace.records, trace.edges, policy)


def build_retained_trace(
    run_state_hash: bytes,
    records: tuple[TraceRecord, ...],
    edges: tuple[TraceEdge, ...],
    policy: TraceRetentionPolicy,
) -> CausalTrace:
    """Build a bounded trace from capture records before packet-model size validation."""
    if not isinstance(policy, TraceRetentionPolicy):
        raise TypeError("trace retention requires a trace retention policy")
    candidates = _level_and_time_records(records, policy)
    retained_records = _retain_records(candidates, policy)
    retained_node_ids = tuple(trace_record_id(record) for record in retained_records)
    edge_candidates = tuple(
        edge
        for edge in edges
        if edge.source_node_id in retained_node_ids and edge.target_node_id in retained_node_ids
    )
    retained_edges = _retain_edges(edge_candidates, policy)
    return CausalTrace(run_state_hash, policy.level, retained_records, retained_edges)


def _level_and_time_records(
    records: tuple[TraceRecord, ...],
    policy: TraceRetentionPolicy,
) -> tuple[TraceRecord, ...]:
    latest_tick = max((record.tick for record in records), default=0)
    earliest_tick = (
        0 if policy.retained_ticks is None else max(0, latest_tick - policy.retained_ticks + 1)
    )
    return tuple(
        record
        for record in records
        if record.tick >= earliest_tick and _included_at_level(record, policy.level)
    )


def _included_at_level(record: TraceRecord, level: TraceLevel) -> bool:
    if level is TraceLevel.FULL:
        return True
    if level is TraceLevel.DECISION:
        return not isinstance(record, ExpressionEvaluationTrace)
    if isinstance(
        record,
        (PolicyInvocationTrace, IntentionTrace, IntentionResolutionTrace, ConsequenceTrace),
    ):
        return True
    return isinstance(record, WorldEventTrace) and record.event_kind in _SUMMARY_WORLD_EVENT_KINDS


def _retain_records(
    records: tuple[TraceRecord, ...],
    policy: TraceRetentionPolicy,
) -> tuple[TraceRecord, ...]:
    if len(records) <= policy.max_records:
        return records
    consequence_event_ids = tuple(
        record.event_id for record in records if isinstance(record, ConsequenceTrace)
    )
    retained_ids: list[TraceNodeId] = []
    for priority in range(8):
        for record in records:
            if (
                _record_priority(record, consequence_event_ids) != priority
                or len(retained_ids) >= policy.max_records
            ):
                continue
            retained_ids.append(trace_record_id(record))
    return tuple(record for record in records if trace_record_id(record) in retained_ids)


def _record_priority(record: TraceRecord, consequence_event_ids: tuple[EventId, ...]) -> int:
    if isinstance(record, ConsequenceTrace):
        return 0
    if isinstance(record, IntentionResolutionTrace):
        return 1
    if isinstance(record, IntentionTrace):
        return 2
    if isinstance(record, WorldEventTrace) and record.event_id in consequence_event_ids:
        return 3
    if isinstance(record, PolicyInvocationTrace):
        return 4
    if isinstance(record, WorldEventTrace):
        return 5
    if isinstance(record, ObservationFactTrace):
        return 6
    return 7


def _retain_edges(
    edges: tuple[TraceEdge, ...], policy: TraceRetentionPolicy
) -> tuple[TraceEdge, ...]:
    if len(edges) <= policy.max_edges:
        return edges
    retained_ids: list[int] = []
    for priority in range(5):
        for edge in edges:
            if _edge_priority(edge) != priority or len(retained_ids) >= policy.max_edges:
                continue
            retained_ids.append(edge.edge_id.value)
    return tuple(edge for edge in edges if edge.edge_id.value in retained_ids)


def _edge_priority(edge: TraceEdge) -> int:
    if edge.kind is TraceEdgeKind.CONTRIBUTED_TO:
        return 0
    if edge.kind in {TraceEdgeKind.REJECTED_BECAUSE, TraceEdgeKind.SELECTED_OVER}:
        return 1
    if edge.kind is TraceEdgeKind.VALIDATED_BY:
        return 2
    if edge.kind is TraceEdgeKind.CAUSED_EVENT:
        return 3
    return 4


def _limit(value: object, maximum: int, label: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= maximum:
        raise ValueError(f"{label} retention limit must be between one and {maximum}")


DEFAULT_TRACE_RETENTION_POLICY = TraceRetentionPolicy()
