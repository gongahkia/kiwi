"""Minimal typed core IR for deterministic Kiwi DSL compilation."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.quantities import Quantity
from kiwi.dsl.ids import DefinitionId, ExpressionId, SymbolId
from kiwi.dsl.intrinsics import IntrinsicKind
from kiwi.dsl.operators import BinaryOperator
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
    OPTION_SOME = "option_some"
    OPTION_NONE = "option_none"
    LIST = "list"
    LAMBDA = "lambda"
    MATCH_OPTION = "match_option"
    RECORD = "record"
    REFERENCE = "reference"
    NEGATE = "negate"
    BINARY = "binary"
    CALL = "call"
    INTRINSIC_CALL = "intrinsic_call"
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
class CoreSome:
    """A payload-bearing built-in `Option` value."""

    expression_id: ExpressionId
    value: CoreExpression
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.OPTION_SOME


@dataclass(frozen=True, slots=True)
class CoreNone:
    """A payload-free built-in `Option` value."""

    expression_id: ExpressionId
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.OPTION_NONE


@dataclass(frozen=True, slots=True)
class CoreList:
    """An immutable source-ordered list literal."""

    expression_id: ExpressionId
    elements: tuple[CoreExpression, ...]
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.LIST


@dataclass(frozen=True, slots=True)
class CoreCapture:
    """One immutable lexical value captured in source-reference order."""

    symbol_id: SymbolId
    type_: DslType


@dataclass(frozen=True, slots=True)
class CoreLambda:
    """An anonymous function body plus explicit captured lexical values."""

    expression_id: ExpressionId
    parameters: tuple[CoreParameter, ...]
    captures: tuple[CoreCapture, ...]
    body: CoreExpression
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.LAMBDA


@dataclass(frozen=True, slots=True)
class CoreMatchSomeArm:
    """The payload-binding arm of a canonical `Option` match."""

    symbol_id: SymbolId
    body: CoreExpression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class CoreMatchNoneArm:
    """The payload-free arm of a canonical `Option` match."""

    body: CoreExpression
    span: SourceSpan


type CoreMatchArm = CoreMatchSomeArm | CoreMatchNoneArm


@dataclass(frozen=True, slots=True)
class CoreMatch:
    """An exhaustive `Option` match retaining source-ordered arms."""

    expression_id: ExpressionId
    subject: CoreExpression
    arms: tuple[CoreMatchArm, ...]
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.MATCH_OPTION


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
class CoreBinary:
    """One checked exact domain operation."""

    expression_id: ExpressionId
    left: CoreExpression
    operator: BinaryOperator
    operator_span: SourceSpan
    right: CoreExpression
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.BINARY


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
class CoreIntrinsicCall:
    """A typed bounded standard-library call."""

    expression_id: ExpressionId
    intrinsic: IntrinsicKind
    arguments: tuple[CoreExpression, ...]
    type_: DslType
    span: SourceSpan
    kind: CoreExpressionKind = CoreExpressionKind.INTRINSIC_CALL


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
    | CoreSome
    | CoreNone
    | CoreList
    | CoreLambda
    | CoreMatch
    | CoreRecord
    | CoreReference
    | CoreNegate
    | CoreBinary
    | CoreCall
    | CoreIntrinsicCall
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
