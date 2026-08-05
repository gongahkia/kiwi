"""Immutable, version-independent causal trace records and typed graph edges."""

from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum, StrEnum

from kiwi.domain.ids import EntityId, EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.ids import ExpressionId, FunctionId
from kiwi.dsl.source import SourceSpan
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionOrigin
from kiwi.sim.limits import MAX_AUTHORITY_TICK

TRACE_HASH_BYTES = 32
MAX_TRACE_RECORDS = 65_536
MAX_TRACE_EDGES = 131_072
MAX_TRACE_TEXT_BYTES = 4_096
MAX_TRACE_PATH_PARTS = 32


class TraceLevel(IntEnum):
    """Retained detail in one captured causal trace."""

    SUMMARY = 1
    DECISION = 2
    FULL = 3


class TraceEdgeKind(StrEnum):
    """Closed semantic reasons one trace record links to another."""

    READ_FROM = "read_from"
    COMPUTED_FROM = "computed_from"
    SELECTED_BRANCH = "selected_branch"
    CONSTRUCTED = "constructed"
    VALIDATED_BY = "validated_by"
    REJECTED_BECAUSE = "rejected_because"
    SELECTED_OVER = "selected_over"
    CAUSED_EVENT = "caused_event"
    CONTRIBUTED_TO = "contributed_to"
    OBSERVED_FROM = "observed_from"
    DERIVED_FROM_MESSAGE = "derived_from_message"


class TraceResolutionStatus(StrEnum):
    """Closed outcome status for an intention-resolution trace record."""

    SELECTED = "selected"
    REJECTED = "rejected"
    FAILED = "failed"


class TraceConsequenceKind(StrEnum):
    """Current major-consequence categories retained by trace version one."""

    INJURY = "injury"
    OBJECTIVE = "objective"
    SYSTEM_FAULT = "system_fault"


@dataclass(frozen=True, slots=True)
class TraceEdgeId:
    """A run-local positive edge identifier outside authoritative allocation."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool) or self.value <= 0:
            raise ValueError("trace edge ID must be positive")


@dataclass(frozen=True, slots=True)
class PolicyInvocationTrace:
    """One policy invocation with exact deployed-policy and memory identities."""

    node_id: TraceNodeId
    tick: int
    entity_id: EntityId
    invocation_id: PolicyInvocationId
    policy_digest: bytes
    entry_function_id: FunctionId
    input_memory_digest: bytes
    result_summary: str

    def __post_init__(self) -> None:
        _node_tick(self.node_id, self.tick)
        if not isinstance(self.entity_id, EntityId):
            raise ValueError("policy invocation trace requires an entity ID")
        if not isinstance(self.invocation_id, PolicyInvocationId):
            raise ValueError("policy invocation trace requires an invocation ID")
        _digest(self.policy_digest, "policy")
        if not isinstance(self.entry_function_id, FunctionId):
            raise ValueError("policy invocation trace requires an entry function ID")
        _digest(self.input_memory_digest, "input memory")
        _text(self.result_summary, "policy invocation result summary")


@dataclass(frozen=True, slots=True)
class ExpressionEvaluationTrace:
    """One source-mapped expression evaluation and concise closed value summary."""

    node_id: TraceNodeId
    tick: int
    invocation_id: PolicyInvocationId
    expression_id: ExpressionId
    source_span: SourceSpan
    value_summary: str

    def __post_init__(self) -> None:
        _node_tick(self.node_id, self.tick)
        if not isinstance(self.invocation_id, PolicyInvocationId):
            raise ValueError("expression trace requires an invocation ID")
        if not isinstance(self.expression_id, ExpressionId):
            raise ValueError("expression trace requires an expression ID")
        if not isinstance(self.source_span, SourceSpan):
            raise ValueError("expression trace requires a source span")
        _text(self.value_summary, "expression value summary")


@dataclass(frozen=True, slots=True)
class ObservationFactTrace:
    """One owner-visible observation field and its evidence event references."""

    node_id: TraceNodeId
    tick: int
    invocation_id: PolicyInvocationId
    path: tuple[str, ...]
    value_summary: str
    evidence_event_ids: tuple[EventId, ...]
    confidence_basis_points: int | None = None
    age_ticks: int | None = None

    def __post_init__(self) -> None:
        _node_tick(self.node_id, self.tick)
        if not isinstance(self.invocation_id, PolicyInvocationId):
            raise ValueError("observation fact trace requires an invocation ID")
        if not isinstance(self.path, tuple) or not 1 <= len(self.path) <= MAX_TRACE_PATH_PARTS:
            raise ValueError("observation fact path must be a bounded non-empty tuple")
        for part in self.path:
            _text(part, "observation fact path part")
        _text(self.value_summary, "observation fact value summary")
        _ascending_ids(self.evidence_event_ids, EventId, "observation fact evidence event IDs")
        if self.confidence_basis_points is not None and (
            not isinstance(self.confidence_basis_points, int)
            or isinstance(self.confidence_basis_points, bool)
            or not 0 <= self.confidence_basis_points <= 10_000
        ):
            raise ValueError("observation fact confidence must be between zero and 10,000")
        if self.age_ticks is not None and (
            not isinstance(self.age_ticks, int)
            or isinstance(self.age_ticks, bool)
            or not 0 <= self.age_ticks <= MAX_AUTHORITY_TICK
        ):
            raise ValueError("observation fact age must fit the authority tick range")


@dataclass(frozen=True, slots=True)
class IntentionTrace:
    """One full source-linked intention origin emitted by a policy invocation."""

    node_id: TraceNodeId
    tick: int
    origin: IntentionOrigin

    def __post_init__(self) -> None:
        _node_tick(self.node_id, self.tick)
        if not isinstance(self.origin, IntentionOrigin):
            raise ValueError("intention trace requires an intention origin")
        if self.origin.creation_tick != self.tick:
            raise ValueError("intention trace tick must match its source origin")


@dataclass(frozen=True, slots=True)
class IntentionResolutionTrace:
    """One validation, arbitration, or execution outcome for an intention."""

    node_id: TraceNodeId
    tick: int
    intention_id: IntentionId
    status: TraceResolutionStatus
    reason_code: str | None
    competing_intention_ids: tuple[IntentionId, ...]
    world_event_ids: tuple[EventId, ...]

    def __post_init__(self) -> None:
        _node_tick(self.node_id, self.tick)
        if not isinstance(self.intention_id, IntentionId):
            raise ValueError("intention resolution trace requires an intention ID")
        if not isinstance(self.status, TraceResolutionStatus):
            raise ValueError("intention resolution trace requires a status")
        if self.reason_code is not None:
            _text(self.reason_code, "intention resolution reason code")
        _ascending_ids(
            self.competing_intention_ids,
            IntentionId,
            "intention resolution competing intention IDs",
        )
        _ascending_ids(self.world_event_ids, EventId, "intention resolution world event IDs")


@dataclass(frozen=True, slots=True)
class WorldEventTrace:
    """One canonical world event exposed as a causal graph record."""

    node_id: TraceNodeId
    tick: int
    event_id: EventId
    event_kind: EventKind
    summary: str

    def __post_init__(self) -> None:
        _node_tick(self.node_id, self.tick)
        if not isinstance(self.event_id, EventId):
            raise ValueError("world event trace requires an event ID")
        if not isinstance(self.event_kind, EventKind):
            raise ValueError("world event trace requires an event kind")
        _text(self.summary, "world event summary")


@dataclass(frozen=True, slots=True)
class ConsequenceTrace:
    """One major tactical consequence with its direct canonical event parent."""

    node_id: TraceNodeId
    tick: int
    kind: TraceConsequenceKind
    subject_entity_ids: tuple[EntityId, ...]
    event_id: EventId
    summary: str

    def __post_init__(self) -> None:
        _node_tick(self.node_id, self.tick)
        if not isinstance(self.kind, TraceConsequenceKind):
            raise ValueError("consequence trace requires a kind")
        _ascending_ids(self.subject_entity_ids, EntityId, "consequence subject entity IDs")
        if not isinstance(self.event_id, EventId):
            raise ValueError("consequence trace requires an event ID")
        _text(self.summary, "consequence summary")


TraceRecord = (
    PolicyInvocationTrace
    | ExpressionEvaluationTrace
    | ObservationFactTrace
    | IntentionTrace
    | IntentionResolutionTrace
    | WorldEventTrace
    | ConsequenceTrace
)


@dataclass(frozen=True, slots=True)
class TraceEdge:
    """One typed, run-local directed relationship between two trace records."""

    edge_id: TraceEdgeId
    source_node_id: TraceNodeId
    target_node_id: TraceNodeId
    kind: TraceEdgeKind

    def __post_init__(self) -> None:
        if not isinstance(self.edge_id, TraceEdgeId):
            raise ValueError("trace edge requires an edge ID")
        if not isinstance(self.source_node_id, TraceNodeId):
            raise ValueError("trace edge requires a source node ID")
        if not isinstance(self.target_node_id, TraceNodeId):
            raise ValueError("trace edge requires a target node ID")
        if self.source_node_id == self.target_node_id:
            raise ValueError("trace edge cannot self-reference")
        if not isinstance(self.kind, TraceEdgeKind):
            raise ValueError("trace edge requires a kind")


@dataclass(frozen=True, slots=True)
class CausalTrace:
    """One immutable run-local trace graph tied to an exact canonical state hash."""

    run_state_hash: bytes
    level: TraceLevel
    records: tuple[TraceRecord, ...]
    edges: tuple[TraceEdge, ...]

    def __post_init__(self) -> None:
        _digest(self.run_state_hash, "trace run state")
        if not isinstance(self.level, TraceLevel):
            raise ValueError("causal trace requires a trace level")
        if not isinstance(self.records, tuple) or len(self.records) > MAX_TRACE_RECORDS:
            raise ValueError("causal trace records must be a bounded immutable tuple")
        previous_node_id = 0
        node_ids: tuple[TraceNodeId, ...] = ()
        for record in self.records:
            node_id = trace_record_id(record)
            if node_id.value <= previous_node_id:
                raise ValueError("causal trace records must be node-ID ordered")
            previous_node_id = node_id.value
            node_ids += (node_id,)
        if not isinstance(self.edges, tuple) or len(self.edges) > MAX_TRACE_EDGES:
            raise ValueError("causal trace edges must be a bounded immutable tuple")
        previous_edge_id = 0
        for edge in self.edges:
            if not isinstance(edge, TraceEdge):
                raise ValueError("causal trace edges must contain trace edges")
            if edge.edge_id.value <= previous_edge_id:
                raise ValueError("causal trace edges must be edge-ID ordered")
            if edge.source_node_id not in node_ids or edge.target_node_id not in node_ids:
                raise ValueError("causal trace edges must reference retained records")
            previous_edge_id = edge.edge_id.value


def trace_record_id(record: TraceRecord) -> TraceNodeId:
    """Return the stable node ID of one closed trace-record variant."""
    if not isinstance(
        record,
        (
            PolicyInvocationTrace,
            ExpressionEvaluationTrace,
            ObservationFactTrace,
            IntentionTrace,
            IntentionResolutionTrace,
            WorldEventTrace,
            ConsequenceTrace,
        ),
    ):
        raise ValueError("trace record requires a supported trace-record variant")
    return record.node_id


def _node_tick(node_id: object, tick: object) -> None:
    if not isinstance(node_id, TraceNodeId):
        raise ValueError("trace record requires a node ID")
    if not isinstance(tick, int) or isinstance(tick, bool) or not 0 <= tick <= MAX_AUTHORITY_TICK:
        raise ValueError("trace record tick must fit the authority tick range")


def _digest(value: object, label: str) -> None:
    if not isinstance(value, bytes) or len(value) != TRACE_HASH_BYTES:
        raise ValueError(f"{label} digest must be {TRACE_HASH_BYTES} bytes")


def _text(value: object, label: str) -> None:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > MAX_TRACE_TEXT_BYTES:
        raise ValueError(f"{label} must be non-empty bounded UTF-8 text")


def _ascending_ids(
    values: object,
    identifier_type: type[object],
    label: str,
) -> None:
    if not isinstance(values, tuple):
        raise ValueError(f"{label} must be an immutable tuple")
    previous = 0
    for value in values:
        if not isinstance(value, identifier_type):
            raise ValueError(f"{label} must be unique and ascending")
        if not isinstance(value, (EntityId, EventId, IntentionId)) or value.value <= previous:
            raise ValueError(f"{label} must be unique and ascending")
        previous = value.value
