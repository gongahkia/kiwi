"""Immutable surface syntax for the Milestone 1 Kiwi DSL grammar."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.quantities import Quantity
from kiwi.dsl.source import SourceSpan


@dataclass(frozen=True, slots=True)
class Identifier:
    """A source-spanned identifier in value or type position."""

    text: str
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class TypeReference:
    """A named surface type annotation."""

    name: Identifier
    span: SourceSpan
    arguments: tuple[TypeReference, ...] = ()


@dataclass(frozen=True, slots=True)
class Parameter:
    """A typed function parameter."""

    name: Identifier
    annotation: TypeReference
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class RecordTypeField:
    """One source-ordered field in a nominal record type declaration."""

    name: Identifier
    annotation: TypeReference
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class IntegerLiteral:
    """An exact integer literal."""

    value: int
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class BooleanLiteral:
    """A boolean literal."""

    value: bool
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class StringLiteral:
    """A decoded immutable string literal."""

    value: str
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class QuantityLiteral:
    """An exact quantity literal normalized to its canonical unit."""

    value: Quantity
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class RecordFieldExpression:
    """One named value supplied while constructing a record."""

    name: Identifier
    value: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class RecordExpression:
    """An immutable nominal record construction expression."""

    type_name: Identifier
    fields: tuple[RecordFieldExpression, ...]
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class SomeExpression:
    """The payload-bearing built-in `Option` variant constructor."""

    value: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class NoneExpression:
    """The payload-free built-in `Option` variant constructor."""

    span: SourceSpan


@dataclass(frozen=True, slots=True)
class SomePattern:
    """A `Some` match arm with one payload binding."""

    binding: Identifier
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class NonePattern:
    """A payload-free `None` match arm."""

    span: SourceSpan


type Pattern = SomePattern | NonePattern


@dataclass(frozen=True, slots=True)
class MatchArm:
    """One source-ordered closed-variant match arm."""

    pattern: Pattern
    body: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class MatchExpression:
    """An exhaustive match over a closed built-in variant."""

    subject: Expression
    arms: tuple[MatchArm, ...]
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class NameExpression:
    """A reference to a surface identifier."""

    name: Identifier
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class NegateExpression:
    """A unary integer negation expression."""

    operand: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class GroupExpression:
    """A parenthesised expression whose span includes the delimiters."""

    expression: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class CallExpression:
    """A function application in source argument order."""

    callee: Expression
    arguments: tuple[Expression, ...]
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class FieldAccessExpression:
    """Read one statically named field from a record expression."""

    record: Expression
    field: Identifier
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class LetExpression:
    """A lexically scoped immutable binding."""

    name: Identifier
    value: Expression
    body: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class IfExpression:
    """A conditional expression with explicit branches."""

    condition: Expression
    then_branch: Expression
    else_branch: Expression
    span: SourceSpan


type Expression = (
    IntegerLiteral
    | BooleanLiteral
    | StringLiteral
    | QuantityLiteral
    | RecordExpression
    | SomeExpression
    | NoneExpression
    | MatchExpression
    | NameExpression
    | NegateExpression
    | GroupExpression
    | CallExpression
    | FieldAccessExpression
    | LetExpression
    | IfExpression
)


@dataclass(frozen=True, slots=True)
class FunctionDeclaration:
    """A named non-policy function declaration."""

    name: Identifier
    parameters: tuple[Parameter, ...]
    return_annotation: TypeReference
    body: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class PolicyDeclaration:
    """A named policy declaration exported by a source module."""

    name: Identifier
    parameters: tuple[Parameter, ...]
    return_annotation: TypeReference
    body: Expression
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class RecordTypeDeclaration:
    """A nominal record schema available in type and construction position."""

    name: Identifier
    fields: tuple[RecordTypeField, ...]
    span: SourceSpan


type ValueDeclaration = FunctionDeclaration | PolicyDeclaration
type Declaration = ValueDeclaration | RecordTypeDeclaration


@dataclass(frozen=True, slots=True)
class SurfaceModule:
    """The complete parsed surface module."""

    declarations: tuple[Declaration, ...]
    span: SourceSpan
