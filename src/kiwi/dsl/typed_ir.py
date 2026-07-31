"""Immutable typed surface representation for the Kiwi DSL."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.quantities import Quantity
from kiwi.dsl.ids import DefinitionId, SymbolId
from kiwi.dsl.source import SourceSpan
from kiwi.dsl.syntax import Identifier
from kiwi.dsl.types import DslType


class TypedDefinitionKind(StrEnum):
    """The source declaration form retained after type checking."""

    FUNCTION = "function"
    POLICY = "policy"


@dataclass(frozen=True, slots=True)
class TypedParameter:
    """A resolved parameter with its checked DSL type."""

    symbol_id: SymbolId
    name: Identifier
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedIntegerLiteral:
    """An integer literal with type `Int`."""

    value: int
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedBooleanLiteral:
    """A boolean literal with type `Bool`."""

    value: bool
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedStringLiteral:
    """A string literal with type `String`."""

    value: str
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedQuantityLiteral:
    """A normalized quantity literal with its dimension-specific type."""

    value: Quantity
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedSomeExpression:
    """A payload-bearing built-in `Option` value."""

    value: TypedExpression
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedNoneExpression:
    """A contextually typed payload-free built-in `Option` value."""

    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedListExpression:
    """A checked immutable list literal with one element type."""

    elements: tuple[TypedExpression, ...]
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedCapture:
    """One source-ordered immutable value captured by an anonymous function."""

    symbol_id: SymbolId
    type_: DslType


@dataclass(frozen=True, slots=True)
class TypedLambdaExpression:
    """An anonymous function with context-checked parameters and captures."""

    parameters: tuple[TypedParameter, ...]
    captures: tuple[TypedCapture, ...]
    body: TypedExpression
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedMatchSomeArm:
    """The payload-binding arm of a checked `Option` match."""

    symbol_id: SymbolId
    binding: Identifier
    body: TypedExpression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedMatchNoneArm:
    """The payload-free arm of a checked `Option` match."""

    body: TypedExpression
    span: SourceSpan


type TypedMatchArm = TypedMatchSomeArm | TypedMatchNoneArm


@dataclass(frozen=True, slots=True)
class TypedMatchExpression:
    """An exhaustive checked `Option` match with source-ordered arms."""

    subject: TypedExpression
    arms: tuple[TypedMatchArm, ...]
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedRecordField:
    """One schema-ordered checked value used to construct a record."""

    name: Identifier
    value: TypedExpression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedRecordExpression:
    """A checked immutable nominal record construction."""

    type_name: str
    fields: tuple[TypedRecordField, ...]
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedNameExpression:
    """A name expression resolved to a lexical symbol."""

    symbol_id: SymbolId
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedNegateExpression:
    """A checked integer negation."""

    operand: TypedExpression
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedGroupExpression:
    """A parenthesised checked expression retaining its source span."""

    expression: TypedExpression
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedCallExpression:
    """A checked call with arguments in source order."""

    callee: TypedExpression
    arguments: tuple[TypedExpression, ...]
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedFieldAccessExpression:
    """A statically resolved read of a record field."""

    record: TypedExpression
    field: Identifier
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedLetExpression:
    """A checked immutable local binding."""

    symbol_id: SymbolId
    name: Identifier
    value: TypedExpression
    body: TypedExpression
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedIfExpression:
    """A checked conditional with equal branch types."""

    condition: TypedExpression
    then_branch: TypedExpression
    else_branch: TypedExpression
    type_: DslType
    span: SourceSpan


type TypedExpression = (
    TypedIntegerLiteral
    | TypedBooleanLiteral
    | TypedStringLiteral
    | TypedQuantityLiteral
    | TypedSomeExpression
    | TypedNoneExpression
    | TypedListExpression
    | TypedLambdaExpression
    | TypedMatchExpression
    | TypedRecordExpression
    | TypedNameExpression
    | TypedNegateExpression
    | TypedGroupExpression
    | TypedCallExpression
    | TypedFieldAccessExpression
    | TypedLetExpression
    | TypedIfExpression
)


@dataclass(frozen=True, slots=True)
class TypedDefinition:
    """One fully checked top-level definition."""

    definition_id: DefinitionId
    symbol_id: SymbolId
    kind: TypedDefinitionKind
    name: Identifier
    parameters: tuple[TypedParameter, ...]
    return_type: DslType
    body: TypedExpression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypedModule:
    """The complete type-checked source module."""

    definitions: tuple[TypedDefinition, ...]
    span: SourceSpan
