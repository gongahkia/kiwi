"""Immutable surface syntax for the Milestone 1 Kiwi DSL grammar."""

from __future__ import annotations

from dataclasses import dataclass

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


@dataclass(frozen=True, slots=True)
class Parameter:
    """A typed function parameter."""

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
    | NameExpression
    | NegateExpression
    | GroupExpression
    | CallExpression
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


type Declaration = FunctionDeclaration | PolicyDeclaration


@dataclass(frozen=True, slots=True)
class SurfaceModule:
    """The complete parsed surface module."""

    declarations: tuple[Declaration, ...]
    span: SourceSpan
