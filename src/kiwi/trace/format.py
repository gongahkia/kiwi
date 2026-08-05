"""Canonical version-one JSON packet codec for immutable causal traces."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from hashlib import blake2b
from typing import cast

from kiwi.domain.ids import EntityId, EventId, IntentionId, PolicyInvocationId, TraceNodeId
from kiwi.dsl.ids import ExpressionId, FunctionId
from kiwi.dsl.source import ByteOffset, SourceFileId, SourceSpan
from kiwi.sim.events import EventKind
from kiwi.sim.intentions import IntentionKind, IntentionOrigin
from kiwi.trace.model import (
    MAX_TRACE_EDGES,
    MAX_TRACE_RECORDS,
    TRACE_HASH_BYTES,
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
    TraceRecord,
    TraceResolutionStatus,
    WorldEventTrace,
)

TRACE_MAGIC = b"KWI-TRACE\x00"
TRACE_VERSION = 1
MAX_ENCODED_TRACE_BYTES = 16 * 1_024 * 1_024
TRACE_HASH_DIGEST_BYTES = 32


class TraceDecodeFailureCode(StrEnum):
    """Stable failures while decoding an untrusted causal trace packet."""

    TOO_LARGE = "TR001_TOO_LARGE"
    INVALID_MAGIC = "TR002_INVALID_MAGIC"
    UNSUPPORTED_VERSION = "TR003_UNSUPPORTED_VERSION"
    INVALID_JSON = "TR004_INVALID_JSON"
    INVALID_STRUCTURE = "TR005_INVALID_STRUCTURE"
    NONCANONICAL = "TR006_NONCANONICAL"


@dataclass(frozen=True, slots=True)
class TraceDecodeFailure:
    """One structured non-throwing failure at the trace-file boundary."""

    code: TraceDecodeFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, TraceDecodeFailureCode):
            raise ValueError("trace decode failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("trace decode failure requires a message")


type TraceDecodeResult = CausalTrace | TraceDecodeFailure


def encode_trace(trace: CausalTrace) -> bytes:
    """Encode one validated trace into canonical version-one packet bytes."""
    if not isinstance(trace, CausalTrace):
        raise TypeError("trace encoding requires a causal trace")
    payload = json.dumps(
        _trace_object(trace),
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    encoded = TRACE_MAGIC + TRACE_VERSION.to_bytes(2, "big") + payload
    if len(encoded) > MAX_ENCODED_TRACE_BYTES:
        raise ValueError("encoded trace exceeds the configured byte limit")
    return encoded


def decode_trace(data: bytes) -> TraceDecodeResult:
    """Decode and validate canonical version-one trace bytes without authority access."""
    if not isinstance(data, bytes):
        raise TypeError("trace decoding requires bytes")
    if len(data) > MAX_ENCODED_TRACE_BYTES:
        return _failure(TraceDecodeFailureCode.TOO_LARGE, "trace exceeds the configured byte limit")
    prefix_length = len(TRACE_MAGIC) + 2
    if len(data) < prefix_length or data[: len(TRACE_MAGIC)] != TRACE_MAGIC:
        return _failure(TraceDecodeFailureCode.INVALID_MAGIC, "trace packet magic is invalid")
    version = int.from_bytes(data[len(TRACE_MAGIC) : prefix_length], "big")
    if version != TRACE_VERSION:
        return _failure(
            TraceDecodeFailureCode.UNSUPPORTED_VERSION,
            f"unsupported trace format version {version}",
        )
    try:
        payload = json.loads(data[prefix_length:].decode("utf-8"), object_pairs_hook=_unique_object)
    except UnicodeDecodeError:
        return _failure(TraceDecodeFailureCode.INVALID_JSON, "trace payload is not valid UTF-8")
    except json.JSONDecodeError:
        return _failure(TraceDecodeFailureCode.INVALID_JSON, "trace payload is not valid JSON")
    except _DuplicateFieldError:
        return _failure(
            TraceDecodeFailureCode.INVALID_STRUCTURE, "trace payload has duplicate fields"
        )
    try:
        trace = _parse_trace(payload)
    except _TraceFormatError as error:
        return _failure(TraceDecodeFailureCode.INVALID_STRUCTURE, error.message)
    if encode_trace(trace) != data:
        return _failure(
            TraceDecodeFailureCode.NONCANONICAL, "trace packet is not canonically encoded"
        )
    return trace


def hash_trace(trace: CausalTrace) -> bytes:
    """Return the fixed BLAKE2b-256 digest of canonical trace packet bytes."""
    return blake2b(encode_trace(trace), digest_size=TRACE_HASH_DIGEST_BYTES).digest()


def _trace_object(trace: CausalTrace) -> dict[str, object]:
    return {
        "edges": [_edge_object(edge) for edge in trace.edges],
        "level": int(trace.level),
        "records": [_record_object(record) for record in trace.records],
        "run_state_hash": trace.run_state_hash.hex(),
    }


def _record_object(record: TraceRecord) -> dict[str, object]:
    base: dict[str, object] = {"node_id": record.node_id.value, "tick": record.tick}
    if isinstance(record, PolicyInvocationTrace):
        return base | {
            "entry_function_id": record.entry_function_id.value,
            "entity_id": record.entity_id.value,
            "input_memory_digest": record.input_memory_digest.hex(),
            "invocation_id": record.invocation_id.value,
            "policy_digest": record.policy_digest.hex(),
            "record_type": "policy_invocation",
            "result_summary": record.result_summary,
        }
    if isinstance(record, ExpressionEvaluationTrace):
        return base | {
            "expression_id": record.expression_id.value,
            "invocation_id": record.invocation_id.value,
            "record_type": "expression_evaluation",
            "source_span": _span_object(record.source_span),
            "value_summary": record.value_summary,
        }
    if isinstance(record, ObservationFactTrace):
        return base | {
            "age_ticks": record.age_ticks,
            "confidence_basis_points": record.confidence_basis_points,
            "evidence_event_ids": [event_id.value for event_id in record.evidence_event_ids],
            "invocation_id": record.invocation_id.value,
            "path": list(record.path),
            "record_type": "observation_fact",
            "value_summary": record.value_summary,
        }
    if isinstance(record, IntentionTrace):
        return base | {"origin": _origin_object(record.origin), "record_type": "intention"}
    if isinstance(record, IntentionResolutionTrace):
        return base | {
            "competing_intention_ids": [
                intention_id.value for intention_id in record.competing_intention_ids
            ],
            "intention_id": record.intention_id.value,
            "reason_code": record.reason_code,
            "record_type": "intention_resolution",
            "status": record.status.value,
            "world_event_ids": [event_id.value for event_id in record.world_event_ids],
        }
    if isinstance(record, WorldEventTrace):
        return base | {
            "event_id": record.event_id.value,
            "event_kind": record.event_kind.value,
            "record_type": "world_event",
            "summary": record.summary,
        }
    if isinstance(record, ConsequenceTrace):
        return base | {
            "consequence_kind": record.kind.value,
            "event_id": record.event_id.value,
            "record_type": "consequence",
            "subject_entity_ids": [entity_id.value for entity_id in record.subject_entity_ids],
            "summary": record.summary,
        }
    raise AssertionError("unsupported trace record")


def _edge_object(edge: TraceEdge) -> dict[str, object]:
    return {
        "edge_id": edge.edge_id.value,
        "kind": edge.kind.value,
        "source_node_id": edge.source_node_id.value,
        "target_node_id": edge.target_node_id.value,
    }


def _origin_object(origin: IntentionOrigin) -> dict[str, object]:
    return {
        "creation_tick": origin.creation_tick,
        "expression_id": origin.source_expression_id.value,
        "intention_id": origin.intention_id.value,
        "intention_kind": origin.kind.value,
        "invocation_id": origin.invocation_id.value,
        "issuer_entity_id": origin.issuer_entity_id.value,
        "policy_order": origin.policy_order,
        "source_span": _span_object(origin.source_span),
    }


def _span_object(span: SourceSpan) -> dict[str, object]:
    return {"end": span.end.value, "file_id": span.file_id.value, "start": span.start.value}


def _parse_trace(value: object) -> CausalTrace:
    root = _mapping(value, "trace")
    _fields(root, {"edges", "level", "records", "run_state_hash"}, "trace")
    records_value = _list(root["records"], "trace records")
    if len(records_value) > MAX_TRACE_RECORDS:
        raise _TraceFormatError("trace record count exceeds the configured limit")
    edges_value = _list(root["edges"], "trace edges")
    if len(edges_value) > MAX_TRACE_EDGES:
        raise _TraceFormatError("trace edge count exceeds the configured limit")
    try:
        return CausalTrace(
            _digest(root["run_state_hash"], "trace run state"),
            TraceLevel(_integer(root["level"], "trace level")),
            tuple(_parse_record(item) for item in records_value),
            tuple(_parse_edge(item) for item in edges_value),
        )
    except (TypeError, ValueError) as error:
        raise _TraceFormatError(str(error)) from error


def _parse_record(value: object) -> TraceRecord:
    record = _mapping(value, "trace record")
    record_type = _text(record.get("record_type"), "trace record type")
    common = (
        TraceNodeId(_integer(record.get("node_id"), "trace record node ID")),
        _integer(record.get("tick"), "trace record tick"),
    )
    try:
        if record_type == "policy_invocation":
            _fields(
                record,
                {
                    "entry_function_id",
                    "entity_id",
                    "input_memory_digest",
                    "invocation_id",
                    "node_id",
                    "policy_digest",
                    "record_type",
                    "result_summary",
                    "tick",
                },
                record_type,
            )
            return PolicyInvocationTrace(
                *common,
                EntityId(_integer(record["entity_id"], "entity ID")),
                PolicyInvocationId(_integer(record["invocation_id"], "invocation ID")),
                _digest(record["policy_digest"], "policy"),
                FunctionId(_integer(record["entry_function_id"], "entry function ID")),
                _digest(record["input_memory_digest"], "input memory"),
                _text(record["result_summary"], "result summary"),
            )
        if record_type == "expression_evaluation":
            _fields(
                record,
                {
                    "expression_id",
                    "invocation_id",
                    "node_id",
                    "record_type",
                    "source_span",
                    "tick",
                    "value_summary",
                },
                record_type,
            )
            return ExpressionEvaluationTrace(
                *common,
                PolicyInvocationId(_integer(record["invocation_id"], "invocation ID")),
                ExpressionId(_integer(record["expression_id"], "expression ID")),
                _parse_span(record["source_span"]),
                _text(record["value_summary"], "value summary"),
            )
        if record_type == "observation_fact":
            _fields(
                record,
                {
                    "age_ticks",
                    "confidence_basis_points",
                    "evidence_event_ids",
                    "invocation_id",
                    "node_id",
                    "path",
                    "record_type",
                    "tick",
                    "value_summary",
                },
                record_type,
            )
            return ObservationFactTrace(
                *common,
                PolicyInvocationId(_integer(record["invocation_id"], "invocation ID")),
                tuple(
                    _text(item, "observation path part")
                    for item in _list(record["path"], "observation path")
                ),
                _text(record["value_summary"], "value summary"),
                cast(
                    tuple[EventId, ...],
                    _ids(
                        _list(record["evidence_event_ids"], "evidence event IDs"),
                        EventId,
                        "evidence event ID",
                    ),
                ),
                _optional_integer(record["confidence_basis_points"], "confidence"),
                _optional_integer(record["age_ticks"], "age"),
            )
        if record_type == "intention":
            _fields(record, {"node_id", "origin", "record_type", "tick"}, record_type)
            return IntentionTrace(*common, _parse_origin(record["origin"]))
        if record_type == "intention_resolution":
            _fields(
                record,
                {
                    "competing_intention_ids",
                    "intention_id",
                    "node_id",
                    "reason_code",
                    "record_type",
                    "status",
                    "tick",
                    "world_event_ids",
                },
                record_type,
            )
            return IntentionResolutionTrace(
                *common,
                IntentionId(_integer(record["intention_id"], "intention ID")),
                TraceResolutionStatus(_text(record["status"], "resolution status")),
                _optional_text(record["reason_code"], "reason code"),
                cast(
                    tuple[IntentionId, ...],
                    _ids(
                        _list(record["competing_intention_ids"], "competing intention IDs"),
                        IntentionId,
                        "competing intention ID",
                    ),
                ),
                cast(
                    tuple[EventId, ...],
                    _ids(
                        _list(record["world_event_ids"], "world event IDs"),
                        EventId,
                        "world event ID",
                    ),
                ),
            )
        if record_type == "world_event":
            _fields(
                record,
                {"event_id", "event_kind", "node_id", "record_type", "summary", "tick"},
                record_type,
            )
            return WorldEventTrace(
                *common,
                EventId(_integer(record["event_id"], "event ID")),
                EventKind(_text(record["event_kind"], "event kind")),
                _text(record["summary"], "event summary"),
            )
        if record_type == "consequence":
            _fields(
                record,
                {
                    "consequence_kind",
                    "event_id",
                    "node_id",
                    "record_type",
                    "subject_entity_ids",
                    "summary",
                    "tick",
                },
                record_type,
            )
            return ConsequenceTrace(
                *common,
                TraceConsequenceKind(_text(record["consequence_kind"], "consequence kind")),
                cast(
                    tuple[EntityId, ...],
                    _ids(
                        _list(record["subject_entity_ids"], "subject entity IDs"),
                        EntityId,
                        "subject entity ID",
                    ),
                ),
                EventId(_integer(record["event_id"], "event ID")),
                _text(record["summary"], "consequence summary"),
            )
    except (TypeError, ValueError) as error:
        raise _TraceFormatError(str(error)) from error
    raise _TraceFormatError("trace record type is unsupported")


def _parse_edge(value: object) -> TraceEdge:
    edge = _mapping(value, "trace edge")
    _fields(edge, {"edge_id", "kind", "source_node_id", "target_node_id"}, "trace edge")
    try:
        return TraceEdge(
            TraceEdgeId(_integer(edge["edge_id"], "edge ID")),
            TraceNodeId(_integer(edge["source_node_id"], "source node ID")),
            TraceNodeId(_integer(edge["target_node_id"], "target node ID")),
            TraceEdgeKind(_text(edge["kind"], "edge kind")),
        )
    except (TypeError, ValueError) as error:
        raise _TraceFormatError(str(error)) from error


def _parse_origin(value: object) -> IntentionOrigin:
    origin = _mapping(value, "intention origin")
    _fields(
        origin,
        {
            "creation_tick",
            "expression_id",
            "intention_id",
            "intention_kind",
            "invocation_id",
            "issuer_entity_id",
            "policy_order",
            "source_span",
        },
        "intention origin",
    )
    try:
        return IntentionOrigin(
            IntentionId(_integer(origin["intention_id"], "intention ID")),
            EntityId(_integer(origin["issuer_entity_id"], "issuer entity ID")),
            PolicyInvocationId(_integer(origin["invocation_id"], "invocation ID")),
            ExpressionId(_integer(origin["expression_id"], "expression ID")),
            _parse_span(origin["source_span"]),
            _integer(origin["policy_order"], "policy order"),
            _integer(origin["creation_tick"], "creation tick"),
            IntentionKind(_text(origin["intention_kind"], "intention kind")),
        )
    except (TypeError, ValueError) as error:
        raise _TraceFormatError(str(error)) from error


def _parse_span(value: object) -> SourceSpan:
    span = _mapping(value, "source span")
    _fields(span, {"end", "file_id", "start"}, "source span")
    try:
        return SourceSpan(
            SourceFileId(_text(span["file_id"], "source file ID")),
            ByteOffset(_integer(span["start"], "source span start")),
            ByteOffset(_integer(span["end"], "source span end")),
        )
    except ValueError as error:
        raise _TraceFormatError(str(error)) from error


def _mapping(value: object, label: str) -> dict[str, object]:
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise _TraceFormatError(f"{label} must be an object")
    return value


def _fields(value: dict[str, object], expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise _TraceFormatError(f"{label} fields are invalid")


def _list(value: object, label: str) -> list[object]:
    if not isinstance(value, list):
        raise _TraceFormatError(f"{label} must be an array")
    return value


def _integer(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise _TraceFormatError(f"{label} must be an integer")
    return value


def _text(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise _TraceFormatError(f"{label} must be text")
    return value


def _optional_text(value: object, label: str) -> str | None:
    return None if value is None else _text(value, label)


def _optional_integer(value: object, label: str) -> int | None:
    return None if value is None else _integer(value, label)


def _digest(value: object, label: str) -> bytes:
    text = _text(value, f"{label} digest")
    try:
        digest = bytes.fromhex(text)
    except ValueError as error:
        raise _TraceFormatError(f"{label} digest is not hexadecimal") from error
    if len(digest) != TRACE_HASH_BYTES or text != digest.hex():
        raise _TraceFormatError(f"{label} digest is invalid")
    return digest


type TraceReferenceId = EntityId | EventId | IntentionId


def _ids(
    values: list[object],
    identifier_type: type[TraceReferenceId],
    label: str,
) -> tuple[TraceReferenceId, ...]:
    try:
        return tuple(identifier_type(_integer(value, label)) for value in values)
    except ValueError as error:
        raise _TraceFormatError(str(error)) from error


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise _DuplicateFieldError()
        value[key] = item
    return value


def _failure(code: TraceDecodeFailureCode, message: str) -> TraceDecodeFailure:
    return TraceDecodeFailure(code, message)


@dataclass(frozen=True, slots=True)
class _TraceFormatError(Exception):
    message: str


@dataclass(frozen=True, slots=True)
class _DuplicateFieldError(Exception):
    pass
