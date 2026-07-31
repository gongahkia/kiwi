"""Closed immutable runtime-value algebra for the initial Kiwi VM."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.domain.quantities import Quantity
from kiwi.dsl.ids import FunctionId

MAX_RUNTIME_STRING_BYTES = 65_536


class RuntimeValueKind(StrEnum):
    """The runtime variants available to Milestone 3 bytecode."""

    INTEGER = "integer"
    BOOLEAN = "boolean"
    UNIT = "unit"
    STRING = "string"
    QUANTITY = "quantity"
    FUNCTION = "function"


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
class FunctionValue:
    """A callable reference into the immutable bytecode function table."""

    function_id: FunctionId
    kind: RuntimeValueKind = field(default=RuntimeValueKind.FUNCTION, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("function value must contain a function ID")


type RuntimeValue = (
    IntegerValue | BooleanValue | UnitValue | StringValue | QuantityValue | FunctionValue
)
