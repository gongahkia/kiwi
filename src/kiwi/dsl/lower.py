"""Deterministically lower typed Kiwi DSL syntax to semantic core IR."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.core_ir import (
    CoreBoolean,
    CoreCall,
    CoreCapture,
    CoreDefinition,
    CoreDefinitionKind,
    CoreExpression,
    CoreFieldAccess,
    CoreIf,
    CoreInteger,
    CoreIntrinsicCall,
    CoreLambda,
    CoreLet,
    CoreList,
    CoreMatch,
    CoreMatchNoneArm,
    CoreMatchSomeArm,
    CoreModule,
    CoreNegate,
    CoreNone,
    CoreParameter,
    CoreQuantity,
    CoreRecord,
    CoreRecordField,
    CoreReference,
    CoreSome,
    CoreString,
)
from kiwi.dsl.ids import DefinitionId, ExpressionId
from kiwi.dsl.source import SourceSpan
from kiwi.dsl.typed_ir import (
    TypedBooleanLiteral,
    TypedCallExpression,
    TypedDefinition,
    TypedDefinitionKind,
    TypedExpression,
    TypedFieldAccessExpression,
    TypedGroupExpression,
    TypedIfExpression,
    TypedIntegerLiteral,
    TypedIntrinsicCallExpression,
    TypedLambdaExpression,
    TypedLetExpression,
    TypedListExpression,
    TypedMatchExpression,
    TypedMatchSomeArm,
    TypedModule,
    TypedNameExpression,
    TypedNegateExpression,
    TypedNoneExpression,
    TypedQuantityLiteral,
    TypedRecordExpression,
    TypedSomeExpression,
    TypedStringLiteral,
)


@dataclass(frozen=True, slots=True)
class SourceMapEntry:
    """The source provenance of one canonical core expression ID."""

    expression_id: ExpressionId
    definition_id: DefinitionId
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class SourceMap:
    """A source-ordered immutable map from core expression IDs to spans."""

    entries: tuple[SourceMapEntry, ...]

    def __post_init__(self) -> None:
        expected_ids = tuple(range(len(self.entries)))
        actual_ids = tuple(entry.expression_id.value for entry in self.entries)
        if actual_ids != expected_ids:
            raise ValueError("source map expression IDs must be contiguous and ordered")

    def entry_for(self, expression_id: ExpressionId) -> SourceMapEntry:
        """Return the provenance entry for a valid core expression ID."""
        try:
            return self.entries[expression_id.value]
        except IndexError as error:
            raise ValueError("source map has no entry for expression ID") from error


@dataclass(frozen=True, slots=True)
class LowerResult:
    """Core output plus the source map required by later compiler stages."""

    module: CoreModule
    source_map: SourceMap


def lower(module: TypedModule) -> LowerResult:
    """Lower typed syntax in definition and expression pre-order."""
    lowerer = _Lowerer()
    definitions = tuple(lowerer.lower_definition(definition) for definition in module.definitions)
    return LowerResult(CoreModule(definitions, module.span), SourceMap(tuple(lowerer.entries)))


class _Lowerer:
    def __init__(self) -> None:
        self.entries: list[SourceMapEntry] = []

    def lower_definition(self, definition: TypedDefinition) -> CoreDefinition:
        kind = (
            CoreDefinitionKind.FUNCTION
            if definition.kind is TypedDefinitionKind.FUNCTION
            else CoreDefinitionKind.POLICY
        )
        return CoreDefinition(
            definition.definition_id,
            definition.symbol_id,
            kind,
            definition.name.text,
            tuple(
                CoreParameter(parameter.symbol_id, parameter.type_, parameter.span)
                for parameter in definition.parameters
            ),
            definition.return_type,
            self.lower_expression(definition.body, definition.definition_id),
            definition.span,
        )

    def lower_expression(
        self,
        expression: TypedExpression,
        definition_id: DefinitionId,
    ) -> CoreExpression:
        if isinstance(expression, TypedGroupExpression):
            return self.lower_expression(expression.expression, definition_id)
        expression_id = ExpressionId(len(self.entries))
        self.entries.append(SourceMapEntry(expression_id, definition_id, expression.span))
        if isinstance(expression, TypedIntegerLiteral):
            return CoreInteger(expression_id, expression.value, expression.type_, expression.span)
        if isinstance(expression, TypedBooleanLiteral):
            return CoreBoolean(expression_id, expression.value, expression.type_, expression.span)
        if isinstance(expression, TypedStringLiteral):
            return CoreString(expression_id, expression.value, expression.type_, expression.span)
        if isinstance(expression, TypedQuantityLiteral):
            return CoreQuantity(expression_id, expression.value, expression.type_, expression.span)
        if isinstance(expression, TypedSomeExpression):
            return CoreSome(
                expression_id,
                self.lower_expression(expression.value, definition_id),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedNoneExpression):
            return CoreNone(expression_id, expression.type_, expression.span)
        if isinstance(expression, TypedListExpression):
            return CoreList(
                expression_id,
                tuple(
                    self.lower_expression(element, definition_id) for element in expression.elements
                ),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedLambdaExpression):
            return CoreLambda(
                expression_id,
                tuple(
                    CoreParameter(parameter.symbol_id, parameter.type_, parameter.span)
                    for parameter in expression.parameters
                ),
                tuple(
                    CoreCapture(capture.symbol_id, capture.type_) for capture in expression.captures
                ),
                self.lower_expression(expression.body, definition_id),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedMatchExpression):
            return CoreMatch(
                expression_id,
                self.lower_expression(expression.subject, definition_id),
                tuple(
                    CoreMatchSomeArm(
                        arm.symbol_id,
                        self.lower_expression(arm.body, definition_id),
                        arm.span,
                    )
                    if isinstance(arm, TypedMatchSomeArm)
                    else CoreMatchNoneArm(
                        self.lower_expression(arm.body, definition_id),
                        arm.span,
                    )
                    for arm in expression.arms
                ),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedRecordExpression):
            return CoreRecord(
                expression_id,
                expression.type_name,
                tuple(
                    CoreRecordField(
                        field.name.text,
                        self.lower_expression(field.value, definition_id),
                        field.span,
                    )
                    for field in expression.fields
                ),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedNameExpression):
            return CoreReference(
                expression_id, expression.symbol_id, expression.type_, expression.span
            )
        if isinstance(expression, TypedNegateExpression):
            return CoreNegate(
                expression_id,
                self.lower_expression(expression.operand, definition_id),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedCallExpression):
            return CoreCall(
                expression_id,
                self.lower_expression(expression.callee, definition_id),
                tuple(
                    self.lower_expression(argument, definition_id)
                    for argument in expression.arguments
                ),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedIntrinsicCallExpression):
            return CoreIntrinsicCall(
                expression_id,
                expression.intrinsic,
                tuple(
                    self.lower_expression(argument, definition_id)
                    for argument in expression.arguments
                ),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedFieldAccessExpression):
            return CoreFieldAccess(
                expression_id,
                self.lower_expression(expression.record, definition_id),
                expression.field.text,
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedLetExpression):
            return CoreLet(
                expression_id,
                expression.symbol_id,
                self.lower_expression(expression.value, definition_id),
                self.lower_expression(expression.body, definition_id),
                expression.type_,
                expression.span,
            )
        if isinstance(expression, TypedIfExpression):
            return CoreIf(
                expression_id,
                self.lower_expression(expression.condition, definition_id),
                self.lower_expression(expression.then_branch, definition_id),
                self.lower_expression(expression.else_branch, definition_id),
                expression.type_,
                expression.span,
            )
        raise TypeError(f"unsupported typed expression: {type(expression).__name__}")
