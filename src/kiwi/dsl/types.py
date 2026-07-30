"""Immutable type algebra for the Kiwi DSL."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class BuiltinType(StrEnum):
    """Primitive types defined by the initial language."""

    INT = "Int"
    BOOL = "Bool"
    UNIT = "Unit"


@dataclass(frozen=True, slots=True)
class NamedType:
    """A named type awaiting resolution in its declared type environment."""

    name: str

    def __post_init__(self) -> None:
        if not self.name:
            raise ValueError("named type name must not be empty")


@dataclass(frozen=True, slots=True)
class FunctionType:
    """A function with one or more ordered parameter types."""

    parameters: tuple[DslType, ...]
    return_type: DslType

    def __post_init__(self) -> None:
        if not self.parameters:
            raise ValueError("function type must have at least one parameter")
        if any(
            not isinstance(parameter, (BuiltinType, NamedType, FunctionType))
            for parameter in self.parameters
        ):
            raise TypeError("function type parameters must be DSL types")
        if not isinstance(self.return_type, (BuiltinType, NamedType, FunctionType)):
            raise TypeError("function return type must be a DSL type")


type DslType = BuiltinType | NamedType | FunctionType


def render_type(type_: DslType) -> str:
    """Render a DSL type with stable, unambiguous function parentheses."""
    match type_:
        case BuiltinType():
            return str(type_)
        case NamedType(name):
            return name
        case FunctionType(parameters, return_type):
            rendered_parameters = tuple(_render_parameter(parameter) for parameter in parameters)
            left = (
                rendered_parameters[0]
                if len(rendered_parameters) == 1
                else f"({', '.join(rendered_parameters)})"
            )
            return f"{left} -> {render_type(return_type)}"


def _render_parameter(type_: DslType) -> str:
    rendered = render_type(type_)
    return f"({rendered})" if isinstance(type_, FunctionType) else rendered
