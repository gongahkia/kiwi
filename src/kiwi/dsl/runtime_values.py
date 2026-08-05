"""Closed immutable runtime-value algebra for the initial Kiwi VM."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.ids import EventId
from kiwi.domain.quantities import Quantity
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.intrinsics import IntrinsicKind

MAX_RUNTIME_STRING_BYTES = 65_536
MAX_RUNTIME_LIST_ITEMS = 1_024
MAX_RUNTIME_CLOSURE_CAPTURES = 64
MAX_OBSERVATION_PATH_PARTS = 32
MAX_OBSERVATION_EVIDENCE_EVENTS = 64


class RuntimeValueKind(StrEnum):
    """The runtime variants available to Milestone 3 bytecode."""

    INTEGER = "integer"
    BOOLEAN = "boolean"
    UNIT = "unit"
    STRING = "string"
    QUANTITY = "quantity"
    OPTION_SOME = "option_some"
    OPTION_NONE = "option_none"
    LIST = "list"
    RECORD = "record"
    FUNCTION = "function"
    CLOSURE = "closure"
    INTRINSIC = "intrinsic"


@dataclass(frozen=True, slots=True)
class IntegerValue:
    """An exact integer runtime value."""

    value: int
    kind: RuntimeValueKind = field(default=RuntimeValueKind.INTEGER, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.value, int) or isinstance(self.value, bool):
            raise ValueError("integer value must be an integer")


@dataclass(frozen=True, slots=True)
class BooleanValue:
    """A boolean runtime value distinct from an integer."""

    value: bool
    kind: RuntimeValueKind = field(default=RuntimeValueKind.BOOLEAN, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.value, bool):
            raise ValueError("boolean value must be a boolean")


@dataclass(frozen=True, slots=True)
class UnitValue:
    """The sole runtime inhabitant of `Unit`."""

    kind: RuntimeValueKind = field(default=RuntimeValueKind.UNIT, init=False)


@dataclass(frozen=True, slots=True)
class StringValue:
    """An immutable UTF-8-bounded string value."""

    value: str
    kind: RuntimeValueKind = field(default=RuntimeValueKind.STRING, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.value, str):
            raise ValueError("string value must be a string")
        if len(self.value.encode("utf-8")) > MAX_RUNTIME_STRING_BYTES:
            raise ValueError("string value exceeds the configured byte limit")


@dataclass(frozen=True, slots=True)
class QuantityValue:
    """A closed exact domain-quantity runtime value."""

    value: Quantity
    kind: RuntimeValueKind = field(default=RuntimeValueKind.QUANTITY, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.value, Quantity):
            raise ValueError("quantity value must be a quantity")


@dataclass(frozen=True, slots=True)
class OptionSomeValue:
    """An immutable `Option` value that contains one closed runtime value."""

    value: RuntimeValue
    kind: RuntimeValueKind = field(default=RuntimeValueKind.OPTION_SOME, init=False)

    def __post_init__(self) -> None:
        if not _is_runtime_value(self.value):
            raise ValueError("option payload must be a runtime value")


@dataclass(frozen=True, slots=True)
class OptionNoneValue:
    """The immutable payload-free `Option` value."""

    kind: RuntimeValueKind = field(default=RuntimeValueKind.OPTION_NONE, init=False)


@dataclass(frozen=True, slots=True)
class ListValue:
    """An immutable bounded sequence with source-preserved element order."""

    values: tuple[RuntimeValue, ...]
    kind: RuntimeValueKind = field(default=RuntimeValueKind.LIST, init=False)

    def __post_init__(self) -> None:
        if len(self.values) > MAX_RUNTIME_LIST_ITEMS:
            raise ValueError("list value exceeds the configured item limit")
        if any(not _is_runtime_value(value) for value in self.values):
            raise ValueError("list values must be runtime values")


@dataclass(frozen=True, slots=True)
class ObservationFieldMetadata:
    """Non-authoritative provenance retained for one observable record field."""

    path: tuple[str, ...]
    evidence_event_ids: tuple[EventId, ...] = ()
    confidence_basis_points: int | None = None
    age_ticks: int | None = None

    def __post_init__(self) -> None:
        if (
            not isinstance(self.path, tuple)
            or not 1 <= len(self.path) <= MAX_OBSERVATION_PATH_PARTS
        ):
            raise ValueError("observation field metadata path must be a bounded non-empty tuple")
        if any(not isinstance(part, str) or not part for part in self.path):
            raise ValueError("observation field metadata path parts must be non-empty strings")
        if not isinstance(self.evidence_event_ids, tuple):
            raise ValueError("observation field metadata evidence IDs must be an immutable tuple")
        if len(self.evidence_event_ids) > MAX_OBSERVATION_EVIDENCE_EVENTS:
            raise ValueError("observation field metadata evidence IDs exceed the configured limit")
        previous_id = 0
        for event_id in self.evidence_event_ids:
            if not isinstance(event_id, EventId):
                raise ValueError("observation field metadata evidence IDs must contain event IDs")
            if event_id.value <= previous_id:
                raise ValueError(
                    "observation field metadata evidence IDs must be unique and ascending"
                )
            previous_id = event_id.value
        if self.confidence_basis_points is not None and (
            not isinstance(self.confidence_basis_points, int)
            or isinstance(self.confidence_basis_points, bool)
            or not 0 <= self.confidence_basis_points <= 10_000
        ):
            raise ValueError(
                "observation field metadata confidence must be between zero and 10,000"
            )
        if self.age_ticks is not None and (
            not isinstance(self.age_ticks, int)
            or isinstance(self.age_ticks, bool)
            or self.age_ticks < 0
        ):
            raise ValueError("observation field metadata age must be a non-negative integer")


@dataclass(frozen=True, slots=True)
class RecordValue:
    """An immutable nominal record with lexically ordered field names."""

    type_name: str
    field_names: tuple[str, ...]
    values: tuple[RuntimeValue, ...]
    kind: RuntimeValueKind = field(default=RuntimeValueKind.RECORD, init=False)
    observation_fields: tuple[ObservationFieldMetadata, ...] = field(
        default=(), compare=False, repr=False, kw_only=True
    )

    def __post_init__(self) -> None:
        if not isinstance(self.type_name, str) or not self.type_name:
            raise ValueError("record type name must be a non-empty string")
        if len(self.field_names) != len(self.values):
            raise ValueError("record field names and values must have equal length")
        if any(not isinstance(name, str) or not name for name in self.field_names):
            raise ValueError("record field names must be non-empty strings")
        if self.field_names != tuple(sorted(self.field_names)) or len(set(self.field_names)) != len(
            self.field_names
        ):
            raise ValueError("record field names must be unique and lexically ordered")
        if any(not _is_runtime_value(value) for value in self.values):
            raise ValueError("record values must be runtime values")
        if self.observation_fields:
            if len(self.observation_fields) != len(self.field_names):
                raise ValueError("record observation metadata must cover every field")
            for field_name, metadata in zip(self.field_names, self.observation_fields, strict=True):
                if not isinstance(metadata, ObservationFieldMetadata):
                    raise ValueError("record observation metadata must contain field metadata")
                if metadata.path[-1] != field_name:
                    raise ValueError("record observation metadata path must end at its field name")

    def field_value(self, name: str) -> RuntimeValue | None:
        """Return one statically named field without dictionary iteration."""
        for field_name, value in zip(self.field_names, self.values, strict=True):
            if field_name == name:
                return value
        return None

    def observation_field_metadata(self, name: str) -> ObservationFieldMetadata | None:
        """Return non-authoritative provenance for one directly loaded field."""
        if not self.observation_fields:
            return None
        for field_name, metadata in zip(self.field_names, self.observation_fields, strict=True):
            if field_name == name:
                return metadata
        return None


@dataclass(frozen=True, slots=True)
class FunctionValue:
    """A callable reference into the immutable bytecode function table."""

    function_id: FunctionId
    kind: RuntimeValueKind = field(default=RuntimeValueKind.FUNCTION, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("function value must contain a function ID")


@dataclass(frozen=True, slots=True)
class ClosureValue:
    """A callable function table reference with immutable captured values."""

    function_id: FunctionId
    captures: tuple[RuntimeValue, ...]
    kind: RuntimeValueKind = field(default=RuntimeValueKind.CLOSURE, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("closure must contain a function ID")
        if len(self.captures) > MAX_RUNTIME_CLOSURE_CAPTURES:
            raise ValueError("closure exceeds the configured capture limit")
        if any(not _is_runtime_value(value) for value in self.captures):
            raise ValueError("closure captures must be runtime values")


@dataclass(frozen=True, slots=True)
class IntrinsicValue:
    """A closed VM-dispatched standard-library function identifier."""

    intrinsic: IntrinsicKind
    kind: RuntimeValueKind = field(default=RuntimeValueKind.INTRINSIC, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.intrinsic, IntrinsicKind):
            raise ValueError("intrinsic value must contain an intrinsic kind")


type RuntimeValue = (
    IntegerValue
    | BooleanValue
    | UnitValue
    | StringValue
    | QuantityValue
    | OptionSomeValue
    | OptionNoneValue
    | ListValue
    | RecordValue
    | FunctionValue
    | ClosureValue
    | IntrinsicValue
)


def _is_runtime_value(value: object) -> bool:
    return isinstance(
        value,
        (
            IntegerValue,
            BooleanValue,
            UnitValue,
            StringValue,
            QuantityValue,
            OptionSomeValue,
            OptionNoneValue,
            ListValue,
            RecordValue,
            FunctionValue,
            ClosureValue,
            IntrinsicValue,
        ),
    )


def strip_observation_metadata(value: RuntimeValue) -> RuntimeValue:
    """Return a closed runtime value with trace-only observation metadata removed."""
    if isinstance(value, OptionSomeValue):
        item = strip_observation_metadata(value.value)
        return value if item is value.value else OptionSomeValue(item)
    if isinstance(value, ListValue):
        items = tuple(strip_observation_metadata(item) for item in value.values)
        return (
            value
            if all(item is original for item, original in zip(items, value.values, strict=True))
            else ListValue(items)
        )
    if isinstance(value, RecordValue):
        items = tuple(strip_observation_metadata(item) for item in value.values)
        if (
            not value.observation_fields
            and all(item is original for item, original in zip(items, value.values, strict=True))
            and type(value) is RecordValue
        ):
            return value
        return RecordValue(value.type_name, value.field_names, items)
    if isinstance(value, ClosureValue):
        captures = tuple(strip_observation_metadata(item) for item in value.captures)
        return (
            value
            if all(
                capture is original
                for capture, original in zip(captures, value.captures, strict=True)
            )
            else ClosureValue(value.function_id, captures)
        )
    return value
