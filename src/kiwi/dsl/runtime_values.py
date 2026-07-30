"""Closed immutable runtime-value algebra for the initial Kiwi VM."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.dsl.bytecode import FunctionId


class RuntimeValueKind(StrEnum):
    """The runtime variants available to Milestone 3 bytecode."""

    INTEGER = "integer"
    BOOLEAN = "boolean"
    UNIT = "unit"
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
class FunctionValue:
    """A callable reference into the immutable bytecode function table."""

    function_id: FunctionId
    kind: RuntimeValueKind = field(default=RuntimeValueKind.FUNCTION, init=False)

    def __post_init__(self) -> None:
        if not isinstance(self.function_id, FunctionId):
            raise ValueError("function value must contain a function ID")


type RuntimeValue = IntegerValue | BooleanValue | UnitValue | FunctionValue
