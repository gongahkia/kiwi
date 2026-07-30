"""Static checking for the Milestone 2 Kiwi DSL subset."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.diagnostics import Diagnostic, DiagnosticLabel, DiagnosticSeverity, DiagnosticStage
from kiwi.dsl.ids import DefinitionId, SymbolId
from kiwi.dsl.names import ResolutionResult, ResolvedBinding, SymbolKind
from kiwi.dsl.source import SourceSpan
from kiwi.dsl.syntax import (
    BooleanLiteral,
    CallExpression,
    Expression,
    FunctionDeclaration,
    GroupExpression,
    IfExpression,
    IntegerLiteral,
    LetExpression,
    NameExpression,
    NegateExpression,
    TypeReference,
)
from kiwi.dsl.typed_ir import (
    TypedBooleanLiteral,
    TypedCallExpression,
    TypedDefinition,
    TypedDefinitionKind,
    TypedExpression,
    TypedGroupExpression,
    TypedIfExpression,
    TypedIntegerLiteral,
    TypedLetExpression,
    TypedModule,
    TypedNameExpression,
    TypedNegateExpression,
    TypedParameter,
)
from kiwi.dsl.types import BuiltinType, DslType, FunctionType, render_type


@dataclass(frozen=True, slots=True)
class CheckResult:
    """Typed output or stable diagnostics for a resolved source module."""

    module: TypedModule | None
    diagnostics: tuple[Diagnostic, ...]


@dataclass(frozen=True, slots=True)
class _DefinitionHeader:
    definition_id: DefinitionId
    symbol_id: SymbolId
    kind: TypedDefinitionKind
    parameters: tuple[TypedParameter, ...]
    return_type: DslType
    function_type: FunctionType


def check(resolution: ResolutionResult) -> CheckResult:
    """Type-check a resolver-clean module without executing player source."""
    if resolution.diagnostics:
        return CheckResult(None, resolution.diagnostics)
    diagnostics: list[Diagnostic] = []
    headers = _headers(resolution, diagnostics)
    if diagnostics:
        return CheckResult(None, tuple(diagnostics))
    symbol_types: list[tuple[SymbolId, DslType]] = [
        (header.symbol_id, header.function_type) for header in headers
    ]
    definitions: list[TypedDefinition] = []
    for resolved_definition, header in zip(resolution.definitions, headers, strict=True):
        symbol_types.extend(
            (parameter.symbol_id, parameter.type_) for parameter in header.parameters
        )
        body = _check_expression(
            resolved_definition.declaration.body,
            resolution,
            symbol_types,
            diagnostics,
        )
        if body is None:
            continue
        if body.type_ != header.return_type:
            diagnostics.append(
                _type_mismatch(
                    body.span,
                    header.return_type,
                    body.type_,
                    resolved_definition.declaration.return_annotation.span,
                    "definition is declared here",
                )
            )
            continue
        definitions.append(
            TypedDefinition(
                header.definition_id,
                header.symbol_id,
                header.kind,
                resolved_definition.declaration.name,
                header.parameters,
                header.return_type,
                body,
                resolved_definition.declaration.span,
            )
        )
    if diagnostics:
        return CheckResult(None, tuple(diagnostics))
    return CheckResult(TypedModule(tuple(definitions), resolution.module.span), ())


def _headers(
    resolution: ResolutionResult,
    diagnostics: list[Diagnostic],
) -> tuple[_DefinitionHeader, ...]:
    headers: list[_DefinitionHeader] = []
    for definition in resolution.definitions:
        declaration = definition.declaration
        parameters: list[TypedParameter] = []
        for parameter in declaration.parameters:
            parameter_type = _annotation_type(parameter.annotation, diagnostics)
            binding = _binding_for_identifier(
                resolution.bindings,
                parameter.name.text,
                parameter.name.span.start.value,
                SymbolKind.PARAMETER,
                definition.definition_id,
            )
            if parameter_type is not None:
                parameters.append(
                    TypedParameter(
                        binding.symbol_id, parameter.name, parameter_type, parameter.span
                    )
                )
        return_type = _annotation_type(declaration.return_annotation, diagnostics)
        if len(parameters) != len(declaration.parameters) or return_type is None:
            continue
        kind = (
            TypedDefinitionKind.FUNCTION
            if isinstance(declaration, FunctionDeclaration)
            else TypedDefinitionKind.POLICY
        )
        headers.append(
            _DefinitionHeader(
                definition.definition_id,
                definition.symbol_id,
                kind,
                tuple(parameters),
                return_type,
                FunctionType(tuple(parameter.type_ for parameter in parameters), return_type),
            )
        )
    return tuple(headers)


def _annotation_type(annotation: TypeReference, diagnostics: list[Diagnostic]) -> DslType | None:
    try:
        return BuiltinType(annotation.name.text)
    except ValueError:
        diagnostics.append(
            Diagnostic(
                "E400_UNKNOWN_TYPE",
                DiagnosticSeverity.ERROR,
                f"unknown type '{annotation.name.text}'",
                annotation.span,
                DiagnosticStage.CHECKER,
            )
        )
        return None


def _check_expression(
    expression: Expression,
    resolution: ResolutionResult,
    symbol_types: list[tuple[SymbolId, DslType]],
    diagnostics: list[Diagnostic],
) -> TypedExpression | None:
    if isinstance(expression, IntegerLiteral):
        return TypedIntegerLiteral(expression.value, BuiltinType.INT, expression.span)
    if isinstance(expression, BooleanLiteral):
        return TypedBooleanLiteral(expression.value, BuiltinType.BOOL, expression.span)
    if isinstance(expression, NameExpression):
        binding = resolution.binding_for(expression)
        if binding is None:
            raise AssertionError("resolver-clean module has an unresolved name")
        return TypedNameExpression(
            binding.symbol_id, _type_for_symbol(symbol_types, binding.symbol_id), expression.span
        )
    if isinstance(expression, NegateExpression):
        operand = _check_expression(expression.operand, resolution, symbol_types, diagnostics)
        if operand is None:
            return None
        if operand.type_ != BuiltinType.INT:
            diagnostics.append(_type_mismatch(operand.span, BuiltinType.INT, operand.type_))
            return None
        return TypedNegateExpression(operand, BuiltinType.INT, expression.span)
    if isinstance(expression, GroupExpression):
        inner = _check_expression(expression.expression, resolution, symbol_types, diagnostics)
        if inner is None:
            return None
        return TypedGroupExpression(inner, inner.type_, expression.span)
    if isinstance(expression, CallExpression):
        callee = _check_expression(expression.callee, resolution, symbol_types, diagnostics)
        arguments = tuple(
            _check_expression(argument, resolution, symbol_types, diagnostics)
            for argument in expression.arguments
        )
        if callee is None or any(argument is None for argument in arguments):
            return None
        typed_arguments = tuple(argument for argument in arguments if argument is not None)
        if not isinstance(callee.type_, FunctionType):
            diagnostics.append(
                Diagnostic(
                    "E403_INVALID_CALL",
                    DiagnosticSeverity.ERROR,
                    f"cannot call value of type {render_type(callee.type_)}",
                    expression.callee.span,
                    DiagnosticStage.CHECKER,
                )
            )
            return None
        if len(typed_arguments) != len(callee.type_.parameters):
            diagnostics.append(
                Diagnostic(
                    "E403_INVALID_CALL",
                    DiagnosticSeverity.ERROR,
                    "expected "
                    f"{len(callee.type_.parameters)} arguments but received {len(typed_arguments)}",
                    expression.span,
                    DiagnosticStage.CHECKER,
                )
            )
            return None
        has_mismatch = False
        for argument, parameter_type in zip(typed_arguments, callee.type_.parameters, strict=True):
            if argument.type_ != parameter_type:
                diagnostics.append(_type_mismatch(argument.span, parameter_type, argument.type_))
                has_mismatch = True
        if has_mismatch:
            return None
        return TypedCallExpression(
            callee, typed_arguments, callee.type_.return_type, expression.span
        )
    if isinstance(expression, LetExpression):
        value = _check_expression(expression.value, resolution, symbol_types, diagnostics)
        if value is None:
            return None
        binding = _binding_for_identifier(
            resolution.bindings,
            expression.name.text,
            expression.name.span.start.value,
            SymbolKind.LOCAL,
            None,
        )
        symbol_types.append((binding.symbol_id, value.type_))
        body = _check_expression(expression.body, resolution, symbol_types, diagnostics)
        if body is None:
            return None
        return TypedLetExpression(
            binding.symbol_id, expression.name, value, body, body.type_, expression.span
        )
    if isinstance(expression, IfExpression):
        condition = _check_expression(expression.condition, resolution, symbol_types, diagnostics)
        then_branch = _check_expression(
            expression.then_branch, resolution, symbol_types, diagnostics
        )
        else_branch = _check_expression(
            expression.else_branch, resolution, symbol_types, diagnostics
        )
        if condition is None or then_branch is None or else_branch is None:
            return None
        if condition.type_ != BuiltinType.BOOL:
            diagnostics.append(_type_mismatch(condition.span, BuiltinType.BOOL, condition.type_))
        if then_branch.type_ != else_branch.type_:
            diagnostics.append(
                Diagnostic(
                    "E402_BRANCH_TYPE_MISMATCH",
                    DiagnosticSeverity.ERROR,
                    "if branches have types "
                    f"{render_type(then_branch.type_)} and {render_type(else_branch.type_)}",
                    else_branch.span,
                    DiagnosticStage.CHECKER,
                    (DiagnosticLabel(then_branch.span, "then branch is here"),),
                )
            )
        if condition.type_ != BuiltinType.BOOL or then_branch.type_ != else_branch.type_:
            return None
        return TypedIfExpression(
            condition, then_branch, else_branch, then_branch.type_, expression.span
        )
    raise TypeError(f"unsupported surface expression: {type(expression).__name__}")


def _binding_for_identifier(
    bindings: tuple[ResolvedBinding, ...],
    name: str,
    start_offset: int,
    kind: SymbolKind,
    definition_id: DefinitionId | None,
) -> ResolvedBinding:
    for binding in bindings:
        if (
            binding.name.text == name
            and binding.name.span.start.value == start_offset
            and binding.kind is kind
            and (definition_id is None or binding.enclosing_definition_id == definition_id)
        ):
            return binding
    raise AssertionError("resolved binding is absent")


def _type_for_symbol(symbol_types: list[tuple[SymbolId, DslType]], symbol_id: SymbolId) -> DslType:
    for candidate_id, candidate_type in reversed(symbol_types):
        if candidate_id == symbol_id:
            return candidate_type
    raise AssertionError("resolved symbol has no type")


def _type_mismatch(
    primary_span: SourceSpan,
    expected: DslType,
    actual: DslType,
    secondary_span: SourceSpan | None = None,
    secondary_message: str | None = None,
) -> Diagnostic:
    labels: tuple[DiagnosticLabel, ...] = ()
    if secondary_span is not None and secondary_message is not None:
        labels = (DiagnosticLabel(secondary_span, secondary_message),)
    return Diagnostic(
        "E401_TYPE_MISMATCH",
        DiagnosticSeverity.ERROR,
        f"expected {render_type(expected)} but received {render_type(actual)}",
        primary_span,
        DiagnosticStage.CHECKER,
        labels,
    )
