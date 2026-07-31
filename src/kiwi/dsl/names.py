"""Deterministic lexical name resolution for the Kiwi DSL."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.dsl.diagnostics import Diagnostic, DiagnosticLabel, DiagnosticSeverity, DiagnosticStage
from kiwi.dsl.ids import DefinitionId, SymbolId
from kiwi.dsl.syntax import (
    BooleanLiteral,
    CallExpression,
    Expression,
    FieldAccessExpression,
    FunctionDeclaration,
    GroupExpression,
    Identifier,
    IfExpression,
    IntegerLiteral,
    LambdaExpression,
    LetExpression,
    ListExpression,
    MatchExpression,
    NameExpression,
    NegateExpression,
    NoneExpression,
    NonePattern,
    Parameter,
    PolicyDeclaration,
    QuantityLiteral,
    RecordExpression,
    SomeExpression,
    SomePattern,
    StringLiteral,
    SurfaceModule,
    ValueDeclaration,
)


class SymbolKind(StrEnum):
    """The binding form represented by a resolved symbol."""

    DEFINITION = "definition"
    PARAMETER = "parameter"
    LOCAL = "local"
    MATCH_BINDING = "match_binding"
    LAMBDA_PARAMETER = "lambda_parameter"


@dataclass(frozen=True, slots=True)
class ResolvedBinding:
    """A binder with an ID allocated by canonical source traversal."""

    symbol_id: SymbolId
    name: Identifier
    kind: SymbolKind
    enclosing_definition_id: DefinitionId
    arity: int | None = None

    def __post_init__(self) -> None:
        if self.arity is not None and self.arity < 0:
            raise ValueError("binding arity must not be negative")
        if self.kind is SymbolKind.DEFINITION and self.arity is None:
            raise ValueError("definition bindings require an arity")
        if self.kind is not SymbolKind.DEFINITION and self.arity is not None:
            raise ValueError("only definition bindings may have an arity")


@dataclass(frozen=True, slots=True)
class ResolvedDefinition:
    """A top-level declaration and its durable compiler IDs."""

    definition_id: DefinitionId
    symbol_id: SymbolId
    declaration: ValueDeclaration


@dataclass(frozen=True, slots=True)
class ResolvedReference:
    """A resolved source name expression."""

    expression: NameExpression
    symbol_id: SymbolId


@dataclass(frozen=True, slots=True)
class LexicalEnvironment:
    """One immutable lexical scope linked to its enclosing scope."""

    bindings: tuple[ResolvedBinding, ...] = ()
    parent: LexicalEnvironment | None = None

    def lookup(self, name: str) -> ResolvedBinding | None:
        """Find the nearest binding for `name` without iterating unordered state."""
        scope: LexicalEnvironment | None = self
        while scope is not None:
            for binding in reversed(scope.bindings):
                if binding.name.text == name:
                    return binding
            scope = scope.parent
        return None

    def extend(self, bindings: tuple[ResolvedBinding, ...]) -> LexicalEnvironment:
        """Return a child scope containing bindings in their declared order."""
        return LexicalEnvironment(bindings, self)


@dataclass(frozen=True, slots=True)
class ResolutionResult:
    """Name-resolution output ordered entirely by source traversal."""

    module: SurfaceModule
    definitions: tuple[ResolvedDefinition, ...]
    bindings: tuple[ResolvedBinding, ...]
    references: tuple[ResolvedReference, ...]
    diagnostics: tuple[Diagnostic, ...]

    def binding_for(self, expression: NameExpression) -> ResolvedBinding | None:
        """Return the resolved binding for one source name expression."""
        for reference in self.references:
            if reference.expression == expression:
                for binding in self.bindings:
                    if binding.symbol_id == reference.symbol_id:
                        return binding
                raise AssertionError("resolved reference has no binding")
        return None


def resolve(module: SurfaceModule) -> ResolutionResult:
    """Resolve module value names in canonical declaration and expression order."""
    value_declarations: tuple[ValueDeclaration, ...] = tuple(
        declaration
        for declaration in module.declarations
        if isinstance(declaration, (FunctionDeclaration, PolicyDeclaration))
    )
    definitions = tuple(
        ResolvedDefinition(DefinitionId(index), SymbolId(index), declaration)
        for index, declaration in enumerate(value_declarations)
    )
    bindings = [
        ResolvedBinding(
            definition.symbol_id,
            definition.declaration.name,
            SymbolKind.DEFINITION,
            definition.definition_id,
            len(definition.declaration.parameters),
        )
        for definition in definitions
    ]
    diagnostics: list[Diagnostic] = []
    global_bindings: list[ResolvedBinding] = []
    for binding in bindings:
        existing = _find_binding(global_bindings, binding.name.text)
        if existing is None:
            global_bindings.append(binding)
            continue
        diagnostics.append(
            _diagnostic(
                "E300_DUPLICATE_DEFINITION",
                f"duplicate definition '{binding.name.text}'",
                binding.name,
                existing.name,
                "first definition is here",
            )
        )

    references: list[ResolvedReference] = []
    next_symbol_value = len(bindings)
    globals_environment = LexicalEnvironment(tuple(global_bindings))
    for definition in definitions:
        declaration = definition.declaration
        parameters, next_symbol_value = _resolve_parameters(
            declaration.parameters,
            definition.definition_id,
            globals_environment,
            next_symbol_value,
            bindings,
            diagnostics,
        )
        environment = globals_environment.extend(tuple(parameters))
        next_symbol_value = _resolve_expression(
            declaration.body,
            environment,
            definition.definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    return ResolutionResult(
        module,
        definitions,
        tuple(bindings),
        tuple(references),
        tuple(diagnostics),
    )


def _resolve_parameters(
    parameters: tuple[Parameter, ...],
    definition_id: DefinitionId,
    globals_environment: LexicalEnvironment,
    next_symbol_value: int,
    bindings: list[ResolvedBinding],
    diagnostics: list[Diagnostic],
) -> tuple[list[ResolvedBinding], int]:
    resolved: list[ResolvedBinding] = []
    for parameter in parameters:
        binding = ResolvedBinding(
            SymbolId(next_symbol_value),
            parameter.name,
            SymbolKind.PARAMETER,
            definition_id,
        )
        next_symbol_value += 1
        bindings.append(binding)
        duplicate = _find_binding(resolved, parameter.name.text)
        if duplicate is not None:
            diagnostics.append(
                _diagnostic(
                    "E302_DUPLICATE_PARAMETER",
                    f"duplicate parameter '{parameter.name.text}'",
                    parameter.name,
                    duplicate.name,
                    "first parameter is here",
                )
            )
            continue
        shadowed = globals_environment.lookup(parameter.name.text)
        if shadowed is not None:
            diagnostics.append(_shadowing_diagnostic(parameter.name, shadowed))
            continue
        resolved.append(binding)
    return resolved, next_symbol_value


def _resolve_lambda_parameters(
    parameters: tuple[Identifier, ...],
    definition_id: DefinitionId,
    environment: LexicalEnvironment,
    next_symbol_value: int,
    bindings: list[ResolvedBinding],
    diagnostics: list[Diagnostic],
) -> tuple[list[ResolvedBinding], int]:
    """Resolve one anonymous function's unannotated lexical parameters."""
    resolved: list[ResolvedBinding] = []
    for parameter in parameters:
        binding = ResolvedBinding(
            SymbolId(next_symbol_value),
            parameter,
            SymbolKind.LAMBDA_PARAMETER,
            definition_id,
        )
        next_symbol_value += 1
        bindings.append(binding)
        duplicate = _find_binding(resolved, parameter.text)
        if duplicate is not None:
            diagnostics.append(
                _diagnostic(
                    "E302_DUPLICATE_PARAMETER",
                    f"duplicate parameter '{parameter.text}'",
                    parameter,
                    duplicate.name,
                    "first parameter is here",
                )
            )
            continue
        shadowed = environment.lookup(parameter.text)
        if shadowed is not None:
            diagnostics.append(_shadowing_diagnostic(parameter, shadowed))
            continue
        resolved.append(binding)
    return resolved, next_symbol_value


def _resolve_expression(
    expression: Expression,
    environment: LexicalEnvironment,
    definition_id: DefinitionId,
    next_symbol_value: int,
    bindings: list[ResolvedBinding],
    references: list[ResolvedReference],
    diagnostics: list[Diagnostic],
) -> int:
    if isinstance(
        expression,
        (IntegerLiteral, BooleanLiteral, StringLiteral, QuantityLiteral, NoneExpression),
    ):
        return next_symbol_value
    if isinstance(expression, SomeExpression):
        return _resolve_expression(
            expression.value,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    if isinstance(expression, ListExpression):
        for element in expression.elements:
            next_symbol_value = _resolve_expression(
                element,
                environment,
                definition_id,
                next_symbol_value,
                bindings,
                references,
                diagnostics,
            )
        return next_symbol_value
    if isinstance(expression, LambdaExpression):
        parameters, next_symbol_value = _resolve_lambda_parameters(
            expression.parameters,
            definition_id,
            environment,
            next_symbol_value,
            bindings,
            diagnostics,
        )
        return _resolve_expression(
            expression.body,
            environment.extend(tuple(parameters)),
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    if isinstance(expression, MatchExpression):
        next_symbol_value = _resolve_expression(
            expression.subject,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
        for arm in expression.arms:
            arm_environment = environment
            if isinstance(arm.pattern, SomePattern):
                pattern_binding = ResolvedBinding(
                    SymbolId(next_symbol_value),
                    arm.pattern.binding,
                    SymbolKind.MATCH_BINDING,
                    definition_id,
                )
                next_symbol_value += 1
                bindings.append(pattern_binding)
                shadowed = environment.lookup(arm.pattern.binding.text)
                if shadowed is not None:
                    diagnostics.append(_shadowing_diagnostic(arm.pattern.binding, shadowed))
                else:
                    arm_environment = environment.extend((pattern_binding,))
            elif not isinstance(arm.pattern, NonePattern):
                raise AssertionError("parser produced an unsupported match pattern")
            next_symbol_value = _resolve_expression(
                arm.body,
                arm_environment,
                definition_id,
                next_symbol_value,
                bindings,
                references,
                diagnostics,
            )
        return next_symbol_value
    if isinstance(expression, RecordExpression):
        for field in expression.fields:
            next_symbol_value = _resolve_expression(
                field.value,
                environment,
                definition_id,
                next_symbol_value,
                bindings,
                references,
                diagnostics,
            )
        return next_symbol_value
    if isinstance(expression, NameExpression):
        binding = environment.lookup(expression.name.text)
        if binding is None:
            diagnostics.append(
                Diagnostic(
                    "E301_UNKNOWN_NAME",
                    DiagnosticSeverity.ERROR,
                    f"unknown name '{expression.name.text}'",
                    expression.name.span,
                    DiagnosticStage.RESOLVER,
                )
            )
        else:
            references.append(ResolvedReference(expression, binding.symbol_id))
        return next_symbol_value
    if isinstance(expression, NegateExpression):
        return _resolve_expression(
            expression.operand,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    if isinstance(expression, GroupExpression):
        return _resolve_expression(
            expression.expression,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    if isinstance(expression, FieldAccessExpression):
        return _resolve_expression(
            expression.record,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    if isinstance(expression, CallExpression):
        next_symbol_value = _resolve_expression(
            expression.callee,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
        for argument in expression.arguments:
            next_symbol_value = _resolve_expression(
                argument,
                environment,
                definition_id,
                next_symbol_value,
                bindings,
                references,
                diagnostics,
            )
        callee = _resolved_callee(expression.callee, bindings, references)
        if callee is not None and callee.kind is SymbolKind.DEFINITION:
            _check_call_arity(expression, callee, len(expression.arguments), diagnostics)
        return next_symbol_value
    if isinstance(expression, LetExpression):
        binding = ResolvedBinding(
            SymbolId(next_symbol_value),
            expression.name,
            SymbolKind.LOCAL,
            definition_id,
        )
        next_symbol_value += 1
        bindings.append(binding)
        next_symbol_value = _resolve_expression(
            expression.value,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
        shadowed = environment.lookup(expression.name.text)
        if shadowed is not None:
            diagnostics.append(_shadowing_diagnostic(expression.name, shadowed))
            body_environment = environment
        else:
            body_environment = environment.extend((binding,))
        return _resolve_expression(
            expression.body,
            body_environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    if isinstance(expression, IfExpression):
        next_symbol_value = _resolve_expression(
            expression.condition,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
        next_symbol_value = _resolve_expression(
            expression.then_branch,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
        return _resolve_expression(
            expression.else_branch,
            environment,
            definition_id,
            next_symbol_value,
            bindings,
            references,
            diagnostics,
        )
    raise TypeError(f"unsupported surface expression: {type(expression).__name__}")


def _resolved_callee(
    expression: Expression,
    bindings: list[ResolvedBinding],
    references: list[ResolvedReference],
) -> ResolvedBinding | None:
    if isinstance(expression, GroupExpression):
        return _resolved_callee(expression.expression, bindings, references)
    if not isinstance(expression, NameExpression):
        return None
    for reference in reversed(references):
        if reference.expression == expression:
            return _binding_for_symbol(bindings, reference.symbol_id)
    return None


def _check_call_arity(
    expression: CallExpression,
    callee: ResolvedBinding,
    actual_arity: int,
    diagnostics: list[Diagnostic],
) -> None:
    if callee.arity == actual_arity:
        return
    diagnostics.append(
        Diagnostic(
            "E304_INVALID_ARITY",
            DiagnosticSeverity.ERROR,
            f"'{callee.name.text}' expects {callee.arity} arguments but received {actual_arity}",
            expression.callee.span,
            DiagnosticStage.RESOLVER,
            (DiagnosticLabel(callee.name.span, "function is declared here"),),
        )
    )


def _shadowing_diagnostic(name: Identifier, shadowed: ResolvedBinding) -> Diagnostic:
    return _diagnostic(
        "E303_PROHIBITED_SHADOWING",
        f"'{name.text}' shadows an active binding",
        name,
        shadowed.name,
        "active binding is here",
    )


def _diagnostic(
    code: str,
    message: str,
    primary: Identifier,
    secondary: Identifier,
    secondary_message: str,
) -> Diagnostic:
    return Diagnostic(
        code,
        DiagnosticSeverity.ERROR,
        message,
        primary.span,
        DiagnosticStage.RESOLVER,
        (DiagnosticLabel(secondary.span, secondary_message),),
    )


def _find_binding(bindings: list[ResolvedBinding], name: str) -> ResolvedBinding | None:
    for binding in bindings:
        if binding.name.text == name:
            return binding
    return None


def _binding_for_symbol(
    bindings: list[ResolvedBinding],
    symbol_id: SymbolId,
) -> ResolvedBinding:
    for binding in bindings:
        if binding.symbol_id == symbol_id:
            return binding
    raise AssertionError("resolved reference has no binding")
