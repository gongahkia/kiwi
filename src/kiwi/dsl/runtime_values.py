"""Closed immutable runtime-value algebra for the initial Kiwi VM."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.quantities import Quantity
from kiwi.dsl.ids import FunctionId

MAX_RUNTIME_STRING_BYTES = 65_536
MAX_RUNTIME_LIST_ITEMS = 1_024
MAX_RUNTIME_CLOSURE_CAPTURES = 64


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
class RecordValue:
    """An immutable nominal record with lexically ordered field names."""

    type_name: str
    field_names: tuple[str, ...]
    values: tuple[RuntimeValue, ...]
    kind: RuntimeValueKind = field(default=RuntimeValueKind.RECORD, init=False)

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

    def field_value(self, name: str) -> RuntimeValue | None:
        """Return one statically named field without dictionary iteration."""
        for field_name, value in zip(self.field_names, self.values, strict=True):
            if field_name == name:
                return value
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
        ),
    )
