"""Minimal typed core IR for deterministic Kiwi DSL compilation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.quantities import Quantity
from kiwi.dsl.ids import DefinitionId, ExpressionId, SymbolId
from kiwi.dsl.source import SourceSpan
from kiwi.dsl.types import DslType


class CoreDefinitionKind(StrEnum):
    """The top-level source declaration form retained in core."""

    FUNCTION = "function"
    POLICY = "policy"


class CoreExpressionKind(StrEnum):
    """The closed semantic expression variants in the initial core."""

    INTEGER = "integer"
    BOOLEAN = "boolean"
    STRING = "string"
    QUANTITY = "quantity"
    RECORD = "record"
    REFERENCE = "reference"
    NEGATE = "negate"
    CALL = "call"
    FIELD_ACCESS = "field_access"
    LET = "let"
    IF = "if"


@dataclass(frozen=True, slots=True)
class CoreInteger:
    """An exact integer core value."""

    expression_id: ExpressionId
    value: int
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.INTEGER


@dataclass(frozen=True, slots=True)
class CoreBoolean:
    """A boolean core value."""

    expression_id: ExpressionId
    value: bool
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.BOOLEAN


@dataclass(frozen=True, slots=True)
class CoreString:
    """An immutable string core value."""

    expression_id: ExpressionId
    value: str
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.STRING


@dataclass(frozen=True, slots=True)
class CoreQuantity:
    """An exact dimension-tagged core value."""

    expression_id: ExpressionId
    value: Quantity
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.QUANTITY


@dataclass(frozen=True, slots=True)
class CoreRecordField:
    """One source-ordered core value used to construct a record."""

    name: str
    value: CoreExpression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class CoreRecord:
    """An immutable nominal record construction."""

    expression_id: ExpressionId
    type_name: str
    fields: tuple[CoreRecordField, ...]
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.RECORD


@dataclass(frozen=True, slots=True)
class CoreReference:
    """A resolved lexical or top-level symbol reference."""

    expression_id: ExpressionId
    symbol_id: SymbolId
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.REFERENCE


@dataclass(frozen=True, slots=True)
class CoreNegate:
    """Integer negation."""

    expression_id: ExpressionId
    operand: CoreExpression
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.NEGATE


@dataclass(frozen=True, slots=True)
class CoreCall:
    """A function call with source-ordered arguments."""

    expression_id: ExpressionId
    callee: CoreExpression
    arguments: tuple[CoreExpression, ...]
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.CALL


@dataclass(frozen=True, slots=True)
class CoreFieldAccess:
    """A statically named record field read."""

    expression_id: ExpressionId
    record: CoreExpression
    field_name: str
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.FIELD_ACCESS


@dataclass(frozen=True, slots=True)
class CoreLet:
    """An immutable local binding represented directly in core."""

    expression_id: ExpressionId
    symbol_id: SymbolId
    value: CoreExpression
    body: CoreExpression
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.LET


@dataclass(frozen=True, slots=True)
class CoreIf:
    """A conditional with checked branch types."""

    expression_id: ExpressionId
    condition: CoreExpression
    then_branch: CoreExpression
    else_branch: CoreExpression
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.IF


type CoreExpression = (
    CoreInteger
    | CoreBoolean
    | CoreString
    | CoreQuantity
    | CoreRecord
    | CoreReference
    | CoreNegate
    | CoreCall
    | CoreFieldAccess
    | CoreLet
    | CoreIf
)


@dataclass(frozen=True, slots=True)
class CoreParameter:
    """A resolved parameter retained for call-frame lowering."""

    symbol_id: SymbolId
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class CoreDefinition:
    """One type-checked top-level core definition."""

    definition_id: DefinitionId
    symbol_id: SymbolId
    kind: CoreDefinitionKind
    name: str
    parameters: tuple[CoreParameter, ...]
    return_type: DslType
    body: CoreExpression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class CoreModule:
    """The complete lowered core module."""

    definitions: tuple[CoreDefinition, ...]
    span: SourceSpan
