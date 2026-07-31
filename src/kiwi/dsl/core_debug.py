"""Stable text rendering for typed core inspection and golden fixtures."""

from __future__ import annotations

from kiwi.dsl.core_ir import (
    CoreBoolean,
    CoreCall,
    CoreDefinition,
    CoreExpression,
    CoreFieldAccess,
    CoreInteger,
    CoreLet,
    CoreModule,
    CoreNegate,
    CoreQuantity,
    CoreRecord,
    CoreReference,
    CoreString,
)
from kiwi.dsl.debug import format_span
from kiwi.dsl.lower import LowerResult, SourceMap
from kiwi.dsl.types import FunctionType, render_type


def format_lower_result(result: LowerResult) -> str:
    """Render core and source-map data in canonical order."""
    lines = _format_core_module(result.module)
    lines.append("  source_map:")
    lines.extend(_format_source_map(result.source_map, 2))
    return "\n".join(lines)


def _format_core_module(module: CoreModule) -> list[str]:
    lines = [f"CoreModule span={format_span(module.span)}", "  definitions:"]
    for definition in module.definitions:
        lines.extend(_format_definition(definition, 2))
    return lines


def _format_definition(definition: CoreDefinition, depth: int) -> list[str]:
    prefix = "  " * depth
    function_type = FunctionType(
        tuple(parameter.type_ for parameter in definition.parameters), definition.return_type
    )
    lines = [
        f"{prefix}Definition id={definition.definition_id.value} "
        f"symbol={definition.symbol_id.value} "
        f"kind={definition.kind.value} name={definition.name!r} type={render_type(function_type)} "
        f"span={format_span(definition.span)}",
        f"{prefix}  parameters:",
    ]
    for parameter in definition.parameters:
        lines.append(
            f"{prefix}    Parameter symbol={parameter.symbol_id.value} "
            f"type={render_type(parameter.type_)} span={format_span(parameter.span)}"
        )
    lines.append(f"{prefix}  body:")
    lines.extend(_format_expression(definition.body, depth + 2))
    return lines


def _format_expression(expression: CoreExpression, depth: int) -> list[str]:
    prefix = "  " * depth
    metadata = (
        f"id={expression.expression_id.value} type={render_type(expression.type_)} "
        f"span={format_span(expression.span)}"
    )
    if isinstance(expression, CoreInteger):
        return [f"{prefix}Integer value={expression.value!r} {metadata}"]
    if isinstance(expression, CoreBoolean):
        return [f"{prefix}Boolean value={expression.value!r} {metadata}"]
    if isinstance(expression, CoreString):
        return [f"{prefix}String value={expression.value!r} {metadata}"]
    if isinstance(expression, CoreQuantity):
        quantity = expression.value
        return [
            f"{prefix}Quantity dimension={quantity.dimension.value} "
            f"value={quantity.value.numerator}/{quantity.value.denominator} {metadata}"
        ]
    if isinstance(expression, CoreRecord):
        lines = [f"{prefix}Record type={expression.type_name!r} {metadata}", f"{prefix}  fields:"]
        for field in expression.fields:
            lines.append(f"{prefix}    Field name={field.name!r} span={format_span(field.span)}")
            lines.extend(_format_expression(field.value, depth + 3))
        return lines
    if isinstance(expression, CoreReference):
        return [f"{prefix}Reference symbol={expression.symbol_id.value} {metadata}"]
    if isinstance(expression, CoreNegate):
        lines = [f"{prefix}Negate {metadata}", f"{prefix}  operand:"]
        lines.extend(_format_expression(expression.operand, depth + 2))
        return lines
    if isinstance(expression, CoreCall):
        lines = [f"{prefix}Call {metadata}", f"{prefix}  callee:"]
        lines.extend(_format_expression(expression.callee, depth + 2))
        lines.append(f"{prefix}  arguments:")
        for argument in expression.arguments:
            lines.extend(_format_expression(argument, depth + 2))
        return lines
    if isinstance(expression, CoreFieldAccess):
        lines = [
            f"{prefix}FieldAccess field={expression.field_name!r} {metadata}",
            f"{prefix}  record:",
        ]
        lines.extend(_format_expression(expression.record, depth + 2))
        return lines
    if isinstance(expression, CoreLet):
        lines = [f"{prefix}Let symbol={expression.symbol_id.value} {metadata}", f"{prefix}  value:"]
        lines.extend(_format_expression(expression.value, depth + 2))
        lines.append(f"{prefix}  body:")
        lines.extend(_format_expression(expression.body, depth + 2))
        return lines
    lines = [f"{prefix}If {metadata}", f"{prefix}  condition:"]
    lines.extend(_format_expression(expression.condition, depth + 2))
    lines.append(f"{prefix}  then_branch:")
    lines.extend(_format_expression(expression.then_branch, depth + 2))
    lines.append(f"{prefix}  else_branch:")
    lines.extend(_format_expression(expression.else_branch, depth + 2))
    return lines


def _format_source_map(source_map: SourceMap, depth: int) -> list[str]:
    prefix = "  " * depth
    return [
        f"{prefix}Entry expression={entry.expression_id.value} "
        f"definition={entry.definition_id.value} "
        f"span={format_span(entry.span)}"
        for entry in source_map.entries
    ]
