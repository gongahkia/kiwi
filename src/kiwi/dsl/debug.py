"""Stable text renderers for DSL token and surface-syntax inspection."""

from __future__ import annotations

from collections.abc import Sequence

from kiwi.dsl.source import SourceSpan
from kiwi.dsl.syntax import (
    BinaryExpression,
    BooleanLiteral,
    CallExpression,
    Declaration,
    Expression,
    FieldAccessExpression,
    FunctionDeclaration,
    FunctionTypeReference,
    GroupExpression,
    Identifier,
    IntegerLiteral,
    LambdaExpression,
    LetExpression,
    ListExpression,
    MatchExpression,
    NameExpression,
    NegateExpression,
    NoneExpression,
    Parameter,
    PolicyDeclaration,
    QuantityLiteral,
    RecordExpression,
    RecordTypeField,
    SomeExpression,
    SomePattern,
    StringLiteral,
    SurfaceModule,
    TypeExpression,
)
from kiwi.dsl.token import Token


def format_tokens(tokens: Sequence[Token]) -> str:
    """Render tokens in caller-supplied lexical order."""
    return "\n".join(
        " ".join(
            (
                f"Token kind={token.kind.value}",
                f"lexeme={token.lexeme!r}",
                f"value={token.value!r}",
                f"span={format_span(token.span)}",
            )
        )
        for token in tokens
    )


def format_surface_module(module: SurfaceModule) -> str:
    """Render an immutable surface module with stable indentation and field order."""
    lines = [f"SurfaceModule span={format_span(module.span)}", "  declarations:"]
    for declaration in module.declarations:
        lines.extend(_format_declaration(declaration, 2))
    return "\n".join(lines)


def format_span(span: SourceSpan) -> str:
    """Render one source span without filesystem or object-identity data."""
    return f"{span.file_id.value!r}@{span.start.value}..{span.end.value}"


def _format_declaration(declaration: Declaration, depth: int) -> list[str]:
    prefix = "  " * depth
    if isinstance(declaration, FunctionDeclaration):
        name = "FunctionDeclaration"
    elif isinstance(declaration, PolicyDeclaration):
        name = "PolicyDeclaration"
    else:
        lines = [
            f"{prefix}RecordTypeDeclaration span={format_span(declaration.span)}",
            f"{prefix}  name:",
        ]
        lines.extend(_format_identifier(declaration.name, depth + 2))
        lines.append(f"{prefix}  fields:")
        for field in declaration.fields:
            lines.extend(_format_record_type_field(field, depth + 2))
        return lines
    lines = [f"{prefix}{name} span={format_span(declaration.span)}", f"{prefix}  name:"]
    lines.extend(_format_identifier(declaration.name, depth + 2))
    lines.append(f"{prefix}  parameters:")
    for parameter in declaration.parameters:
        lines.extend(_format_parameter(parameter, depth + 2))
    lines.append(f"{prefix}  return_annotation:")
    lines.extend(_format_type_reference(declaration.return_annotation, depth + 2))
    lines.append(f"{prefix}  body:")
    lines.extend(_format_expression(declaration.body, depth + 2))
    return lines


def _format_parameter(parameter: Parameter, depth: int) -> list[str]:
    prefix = "  " * depth
    lines = [f"{prefix}Parameter span={format_span(parameter.span)}", f"{prefix}  name:"]
    lines.extend(_format_identifier(parameter.name, depth + 2))
    lines.append(f"{prefix}  annotation:")
    lines.extend(_format_type_reference(parameter.annotation, depth + 2))
    return lines


def _format_record_type_field(field: RecordTypeField, depth: int) -> list[str]:
    prefix = "  " * depth
    lines = [f"{prefix}RecordTypeField span={format_span(field.span)}", f"{prefix}  name:"]
    lines.extend(_format_identifier(field.name, depth + 2))
    lines.append(f"{prefix}  annotation:")
    lines.extend(_format_type_reference(field.annotation, depth + 2))
    return lines


def _format_type_reference(annotation: TypeExpression, depth: int) -> list[str]:
    prefix = "  " * depth
    if isinstance(annotation, FunctionTypeReference):
        lines = [
            f"{prefix}FunctionTypeReference span={format_span(annotation.span)}",
            f"{prefix}  parameters:",
        ]
        for parameter in annotation.parameters:
            lines.extend(_format_type_reference(parameter, depth + 2))
        lines.append(f"{prefix}  return_type:")
        lines.extend(_format_type_reference(annotation.return_type, depth + 2))
        return lines
    lines = [f"{prefix}TypeReference span={format_span(annotation.span)}", f"{prefix}  name:"]
    lines.extend(_format_identifier(annotation.name, depth + 2))
    if annotation.arguments:
        lines.append(f"{prefix}  arguments:")
        for argument in annotation.arguments:
            lines.extend(_format_type_reference(argument, depth + 2))
    return lines


def _format_identifier(identifier: Identifier, depth: int) -> list[str]:
    prefix = "  " * depth
    return [f"{prefix}Identifier text={identifier.text!r} span={format_span(identifier.span)}"]


def _format_expression(expression: Expression, depth: int) -> list[str]:
    prefix = "  " * depth
    if isinstance(expression, IntegerLiteral):
        return [
            f"{prefix}IntegerLiteral value={expression.value!r} span={format_span(expression.span)}"
        ]
    if isinstance(expression, BooleanLiteral):
        return [
            f"{prefix}BooleanLiteral value={expression.value!r} span={format_span(expression.span)}"
        ]
    if isinstance(expression, StringLiteral):
        return [
            f"{prefix}StringLiteral value={expression.value!r} span={format_span(expression.span)}"
        ]
    if isinstance(expression, QuantityLiteral):
        quantity = expression.value
        return [
            f"{prefix}QuantityLiteral dimension={quantity.dimension.value} "
            f"value={quantity.value.numerator}/{quantity.value.denominator} "
            f"span={format_span(expression.span)}"
        ]
    if isinstance(expression, SomeExpression):
        lines = [f"{prefix}SomeExpression span={format_span(expression.span)}", f"{prefix}  value:"]
        lines.extend(_format_expression(expression.value, depth + 2))
        return lines
    if isinstance(expression, NoneExpression):
        return [f"{prefix}NoneExpression span={format_span(expression.span)}"]
    if isinstance(expression, ListExpression):
        lines = [
            f"{prefix}ListExpression span={format_span(expression.span)}",
            f"{prefix}  elements:",
        ]
        for element in expression.elements:
            lines.extend(_format_expression(element, depth + 2))
        return lines
    if isinstance(expression, RecordExpression):
        lines = [
            f"{prefix}RecordExpression span={format_span(expression.span)}",
            f"{prefix}  type_name:",
        ]
        lines.extend(_format_identifier(expression.type_name, depth + 2))
        lines.append(f"{prefix}  fields:")
        for field in expression.fields:
            lines.append(f"{prefix}    RecordField span={format_span(field.span)}")
            lines.append(f"{prefix}      name:")
            lines.extend(_format_identifier(field.name, depth + 4))
            lines.append(f"{prefix}      value:")
            lines.extend(_format_expression(field.value, depth + 4))
        return lines
    if isinstance(expression, NameExpression):
        lines = [f"{prefix}NameExpression span={format_span(expression.span)}", f"{prefix}  name:"]
        lines.extend(_format_identifier(expression.name, depth + 2))
        return lines
    if isinstance(expression, NegateExpression):
        lines = [
            f"{prefix}NegateExpression span={format_span(expression.span)}",
            f"{prefix}  operand:",
        ]
        lines.extend(_format_expression(expression.operand, depth + 2))
        return lines
    if isinstance(expression, BinaryExpression):
        lines = [
            f"{prefix}BinaryExpression operator={expression.operator.name} "
            f"span={format_span(expression.span)}",
            f"{prefix}  left:",
        ]
        lines.extend(_format_expression(expression.left, depth + 2))
        lines.append(f"{prefix}  right:")
        lines.extend(_format_expression(expression.right, depth + 2))
        return lines
    if isinstance(expression, GroupExpression):
        lines = [
            f"{prefix}GroupExpression span={format_span(expression.span)}",
            f"{prefix}  expression:",
        ]
        lines.extend(_format_expression(expression.expression, depth + 2))
        return lines
    if isinstance(expression, CallExpression):
        lines = [
            f"{prefix}CallExpression span={format_span(expression.span)}",
            f"{prefix}  callee:",
        ]
        lines.extend(_format_expression(expression.callee, depth + 2))
        lines.append(f"{prefix}  arguments:")
        for argument in expression.arguments:
            lines.extend(_format_expression(argument, depth + 2))
        return lines
    if isinstance(expression, FieldAccessExpression):
        lines = [
            f"{prefix}FieldAccessExpression span={format_span(expression.span)}",
            f"{prefix}  record:",
        ]
        lines.extend(_format_expression(expression.record, depth + 2))
        lines.append(f"{prefix}  field:")
        lines.extend(_format_identifier(expression.field, depth + 2))
        return lines
    if isinstance(expression, LetExpression):
        lines = [f"{prefix}LetExpression span={format_span(expression.span)}", f"{prefix}  name:"]
        lines.extend(_format_identifier(expression.name, depth + 2))
        lines.append(f"{prefix}  value:")
        lines.extend(_format_expression(expression.value, depth + 2))
        lines.append(f"{prefix}  body:")
        lines.extend(_format_expression(expression.body, depth + 2))
        return lines
    if isinstance(expression, LambdaExpression):
        lines = [
            f"{prefix}LambdaExpression span={format_span(expression.span)}",
            f"{prefix}  parameters:",
        ]
        for parameter in expression.parameters:
            lines.extend(_format_identifier(parameter, depth + 2))
        lines.append(f"{prefix}  body:")
        lines.extend(_format_expression(expression.body, depth + 2))
        return lines
    if isinstance(expression, MatchExpression):
        lines = [
            f"{prefix}MatchExpression span={format_span(expression.span)}",
            f"{prefix}  subject:",
        ]
        lines.extend(_format_expression(expression.subject, depth + 2))
        lines.append(f"{prefix}  arms:")
        for arm in expression.arms:
            if isinstance(arm.pattern, SomePattern):
                lines.append(f"{prefix}    SomePattern span={format_span(arm.pattern.span)}")
                lines.extend(_format_identifier(arm.pattern.binding, depth + 3))
            else:
                lines.append(f"{prefix}    NonePattern span={format_span(arm.pattern.span)}")
            lines.append(f"{prefix}      body:")
            lines.extend(_format_expression(arm.body, depth + 3))
        return lines
    lines = [f"{prefix}IfExpression span={format_span(expression.span)}", f"{prefix}  condition:"]
    lines.extend(_format_expression(expression.condition, depth + 2))
    lines.append(f"{prefix}  then_branch:")
    lines.extend(_format_expression(expression.then_branch, depth + 2))
    lines.append(f"{prefix}  else_branch:")
    lines.extend(_format_expression(expression.else_branch, depth + 2))
    return lines
