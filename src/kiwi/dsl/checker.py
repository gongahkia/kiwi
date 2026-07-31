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
    FieldAccessExpression,
    FunctionDeclaration,
    GroupExpression,
    IfExpression,
    IntegerLiteral,
    LetExpression,
    ListExpression,
    MatchArm,
    MatchExpression,
    NameExpression,
    NegateExpression,
    NoneExpression,
    NonePattern,
    QuantityLiteral,
    RecordExpression,
    RecordTypeDeclaration,
    SomeExpression,
    SomePattern,
    StringLiteral,
    SurfaceModule,
    TypeReference,
)
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
    TypedLetExpression,
    TypedListExpression,
    TypedMatchExpression,
    TypedMatchNoneArm,
    TypedMatchSomeArm,
    TypedModule,
    TypedNameExpression,
    TypedNegateExpression,
    TypedNoneExpression,
    TypedParameter,
    TypedQuantityLiteral,
    TypedRecordExpression,
    TypedRecordField,
    TypedSomeExpression,
    TypedStringLiteral,
)
from kiwi.dsl.types import (
    BuiltinType,
    DslType,
    FunctionType,
    ListType,
    NamedType,
    OptionType,
    render_type,
)


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


@dataclass(frozen=True, slots=True)
class _RecordFieldSchema:
    name: str
    type_: DslType
    span: SourceSpan


@dataclass(frozen=True, slots=True)
class _RecordSchema:
    name: str
    fields: tuple[_RecordFieldSchema, ...]
    span: SourceSpan


def check(resolution: ResolutionResult) -> CheckResult:
    """Type-check a resolver-clean module without executing player source."""
    if resolution.diagnostics:
        return CheckResult(None, resolution.diagnostics)
    diagnostics: list[Diagnostic] = []
    record_schemas = _record_schemas(resolution.module, diagnostics)
    headers = _headers(resolution, record_schemas, diagnostics)
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
            record_schemas,
            header.return_type,
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
    record_schemas: tuple[_RecordSchema, ...],
    diagnostics: list[Diagnostic],
) -> tuple[_DefinitionHeader, ...]:
    headers: list[_DefinitionHeader] = []
    for definition in resolution.definitions:
        declaration = definition.declaration
        parameters: list[TypedParameter] = []
        for parameter in declaration.parameters:
            parameter_type = _annotation_type(parameter.annotation, record_schemas, diagnostics)
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
        return_type = _annotation_type(
            declaration.return_annotation,
            record_schemas,
            diagnostics,
        )
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


def _annotation_type(
    annotation: TypeReference,
    record_schemas: tuple[_RecordSchema, ...],
    diagnostics: list[Diagnostic],
) -> DslType | None:
    if annotation.name.text == "Option":
        if len(annotation.arguments) != 1:
            diagnostics.append(
                Diagnostic(
                    "E411_INVALID_OPTION_TYPE",
                    DiagnosticSeverity.ERROR,
                    "Option requires exactly one type argument",
                    annotation.span,
                    DiagnosticStage.CHECKER,
                )
            )
            return None
        element_type = _annotation_type(annotation.arguments[0], record_schemas, diagnostics)
        return OptionType(element_type) if element_type is not None else None
    if annotation.name.text == "List":
        if len(annotation.arguments) != 1:
            diagnostics.append(
                Diagnostic(
                    "E417_INVALID_LIST_TYPE",
                    DiagnosticSeverity.ERROR,
                    "List requires exactly one type argument",
                    annotation.span,
                    DiagnosticStage.CHECKER,
                )
            )
            return None
        element_type = _annotation_type(annotation.arguments[0], record_schemas, diagnostics)
        return ListType(element_type) if element_type is not None else None
    if annotation.arguments:
        diagnostics.append(
            Diagnostic(
                "E400_UNKNOWN_TYPE",
                DiagnosticSeverity.ERROR,
                f"type '{annotation.name.text}' does not take type arguments",
                annotation.span,
                DiagnosticStage.CHECKER,
            )
        )
        return None
    try:
        return BuiltinType(annotation.name.text)
    except ValueError:
        if _record_schema_for(record_schemas, annotation.name.text) is not None:
            return NamedType(annotation.name.text)
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


def _record_schemas(
    module: SurfaceModule,
    diagnostics: list[Diagnostic],
) -> tuple[_RecordSchema, ...]:
    declarations = tuple(
        declaration
        for declaration in module.declarations
        if isinstance(declaration, RecordTypeDeclaration)
    )
    names: list[str] = []
    accepted: list[RecordTypeDeclaration] = []
    for declaration in declarations:
        if declaration.name.text in names:
            diagnostics.append(
                Diagnostic(
                    "E404_DUPLICATE_RECORD_TYPE",
                    DiagnosticSeverity.ERROR,
                    f"duplicate record type '{declaration.name.text}'",
                    declaration.name.span,
                    DiagnosticStage.CHECKER,
                )
            )
            continue
        if declaration.name.text in {"Option", "List"}:
            diagnostics.append(
                Diagnostic(
                    "E404_DUPLICATE_RECORD_TYPE",
                    DiagnosticSeverity.ERROR,
                    f"record type '{declaration.name.text}' conflicts with a built-in type",
                    declaration.name.span,
                    DiagnosticStage.CHECKER,
                )
            )
            continue
        try:
            BuiltinType(declaration.name.text)
        except ValueError:
            names.append(declaration.name.text)
            accepted.append(declaration)
            continue
        diagnostics.append(
            Diagnostic(
                "E404_DUPLICATE_RECORD_TYPE",
                DiagnosticSeverity.ERROR,
                f"record type '{declaration.name.text}' conflicts with a built-in type",
                declaration.name.span,
                DiagnosticStage.CHECKER,
            )
        )
    schemas: list[_RecordSchema] = []
    placeholder_schemas = tuple(_RecordSchema(name, (), module.span) for name in names)
    for declaration in accepted:
        fields = _record_schema_fields(declaration, placeholder_schemas, diagnostics)
        if fields is not None:
            schemas.append(_RecordSchema(declaration.name.text, fields, declaration.span))
    return tuple(schemas)


def _record_schema_fields(
    declaration: RecordTypeDeclaration,
    record_schemas: tuple[_RecordSchema, ...],
    diagnostics: list[Diagnostic],
) -> tuple[_RecordFieldSchema, ...] | None:
    fields: list[_RecordFieldSchema] = []
    field_names: list[str] = []
    for field in declaration.fields:
        if field.name.text in field_names:
            diagnostics.append(
                Diagnostic(
                    "E405_DUPLICATE_RECORD_FIELD",
                    DiagnosticSeverity.ERROR,
                    f"duplicate field '{field.name.text}' in record type '{declaration.name.text}'",
                    field.name.span,
                    DiagnosticStage.CHECKER,
                )
            )
            continue
        type_ = _annotation_type(field.annotation, record_schemas, diagnostics)
        if type_ is None:
            continue
        field_names.append(field.name.text)
        fields.append(_RecordFieldSchema(field.name.text, type_, field.span))
    return tuple(fields) if len(fields) == len(declaration.fields) else None


def _record_schema_for(
    record_schemas: tuple[_RecordSchema, ...] | list[_RecordSchema],
    name: str,
) -> _RecordSchema | None:
    for schema in record_schemas:
        if schema.name == name:
            return schema
    return None


def _check_expression(
    expression: Expression,
    resolution: ResolutionResult,
    symbol_types: list[tuple[SymbolId, DslType]],
    diagnostics: list[Diagnostic],
    record_schemas: tuple[_RecordSchema, ...],
    expected_type: DslType | None = None,
) -> TypedExpression | None:
    if isinstance(expression, IntegerLiteral):
        return TypedIntegerLiteral(expression.value, BuiltinType.INT, expression.span)
    if isinstance(expression, BooleanLiteral):
        return TypedBooleanLiteral(expression.value, BuiltinType.BOOL, expression.span)
    if isinstance(expression, StringLiteral):
        return TypedStringLiteral(expression.value, BuiltinType.STRING, expression.span)
    if isinstance(expression, QuantityLiteral):
        return TypedQuantityLiteral(
            expression.value,
            BuiltinType(expression.value.dimension.value),
            expression.span,
        )
    if isinstance(expression, SomeExpression):
        expected_element = (
            expected_type.element_type if isinstance(expected_type, OptionType) else None
        )
        value = _check_expression(
            expression.value,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected_element,
        )
        if value is None:
            return None
        type_ = OptionType(value.type_)
        if expected_type is not None and type_ != expected_type:
            diagnostics.append(_type_mismatch(expression.span, expected_type, type_))
            return None
        return TypedSomeExpression(value, type_, expression.span)
    if isinstance(expression, NoneExpression):
        if not isinstance(expected_type, OptionType):
            diagnostics.append(
                Diagnostic(
                    "E412_AMBIGUOUS_NONE",
                    DiagnosticSeverity.ERROR,
                    "None requires an expected Option type",
                    expression.span,
                    DiagnosticStage.CHECKER,
                )
            )
            return None
        return TypedNoneExpression(expected_type, expression.span)
    if isinstance(expression, ListExpression):
        return _check_list_expression(
            expression,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected_type,
        )
    if isinstance(expression, MatchExpression):
        return _check_match_expression(
            expression,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected_type,
        )
    if isinstance(expression, RecordExpression):
        return _check_record_expression(
            expression,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
        )
    if isinstance(expression, NameExpression):
        binding = resolution.binding_for(expression)
        if binding is None:
            raise AssertionError("resolver-clean module has an unresolved name")
        return TypedNameExpression(
            binding.symbol_id, _type_for_symbol(symbol_types, binding.symbol_id), expression.span
        )
    if isinstance(expression, NegateExpression):
        operand = _check_expression(
            expression.operand,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            BuiltinType.INT,
        )
        if operand is None:
            return None
        if operand.type_ != BuiltinType.INT:
            diagnostics.append(_type_mismatch(operand.span, BuiltinType.INT, operand.type_))
            return None
        return TypedNegateExpression(operand, BuiltinType.INT, expression.span)
    if isinstance(expression, GroupExpression):
        inner = _check_expression(
            expression.expression,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected_type,
        )
        if inner is None:
            return None
        return TypedGroupExpression(inner, inner.type_, expression.span)
    if isinstance(expression, FieldAccessExpression):
        return _check_field_access_expression(
            expression,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
        )
    if isinstance(expression, CallExpression):
        callee = _check_expression(
            expression.callee,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
        )
        if callee is None:
            return None
        if not isinstance(callee.type_, FunctionType):
            for argument in expression.arguments:
                _check_expression(argument, resolution, symbol_types, diagnostics, record_schemas)
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
        if len(expression.arguments) != len(callee.type_.parameters):
            for argument in expression.arguments:
                _check_expression(argument, resolution, symbol_types, diagnostics, record_schemas)
            diagnostics.append(
                Diagnostic(
                    "E403_INVALID_CALL",
                    DiagnosticSeverity.ERROR,
                    "expected "
                    f"{len(callee.type_.parameters)} arguments but received "
                    f"{len(expression.arguments)}",
                    expression.span,
                    DiagnosticStage.CHECKER,
                )
            )
            return None
        arguments = tuple(
            _check_expression(
                argument,
                resolution,
                symbol_types,
                diagnostics,
                record_schemas,
                parameter_type,
            )
            for argument, parameter_type in zip(
                expression.arguments,
                callee.type_.parameters,
                strict=True,
            )
        )
        if any(argument is None for argument in arguments):
            return None
        typed_arguments = tuple(item for item in arguments if item is not None)
        for typed_argument, parameter_type in zip(
            typed_arguments, callee.type_.parameters, strict=True
        ):
            if typed_argument.type_ != parameter_type:
                diagnostics.append(
                    _type_mismatch(typed_argument.span, parameter_type, typed_argument.type_)
                )
                return None
        return TypedCallExpression(
            callee, typed_arguments, callee.type_.return_type, expression.span
        )
    if isinstance(expression, LetExpression):
        value = _check_expression(
            expression.value,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
        )
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
        body = _check_expression(
            expression.body,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected_type,
        )
        if body is None:
            return None
        return TypedLetExpression(
            binding.symbol_id, expression.name, value, body, body.type_, expression.span
        )
    if isinstance(expression, IfExpression):
        condition = _check_expression(
            expression.condition,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            BuiltinType.BOOL,
        )
        then_branch = _check_expression(
            expression.then_branch,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected_type,
        )
        if condition is None or then_branch is None:
            return None
        else_branch = _check_expression(
            expression.else_branch,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected_type if expected_type is not None else then_branch.type_,
        )
        if else_branch is None:
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


def _check_list_expression(
    expression: ListExpression,
    resolution: ResolutionResult,
    symbol_types: list[tuple[SymbolId, DslType]],
    diagnostics: list[Diagnostic],
    record_schemas: tuple[_RecordSchema, ...],
    expected_type: DslType | None,
) -> TypedExpression | None:
    expected_element = expected_type.element_type if isinstance(expected_type, ListType) else None
    if not expression.elements:
        if expected_element is None:
            diagnostics.append(
                Diagnostic(
                    "E418_AMBIGUOUS_EMPTY_LIST",
                    DiagnosticSeverity.ERROR,
                    "empty list requires an expected List type",
                    expression.span,
                    DiagnosticStage.CHECKER,
                )
            )
            return None
        return TypedListExpression((), ListType(expected_element), expression.span)
    typed_elements: list[TypedExpression] = []
    element_type: DslType | None = None
    first_element: TypedExpression | None = None
    for element in expression.elements:
        context = element_type if element_type is not None else expected_element
        typed_element = _check_expression(
            element,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            context,
        )
        if typed_element is None:
            return None
        if element_type is None:
            element_type = typed_element.type_
            first_element = typed_element
        elif typed_element.type_ != element_type:
            if first_element is None:
                raise AssertionError("list element type has no first element")
            diagnostics.append(
                Diagnostic(
                    "E419_LIST_ELEMENT_TYPE",
                    DiagnosticSeverity.ERROR,
                    "list elements have types "
                    f"{render_type(element_type)} and {render_type(typed_element.type_)}",
                    typed_element.span,
                    DiagnosticStage.CHECKER,
                    (DiagnosticLabel(first_element.span, "first list element is here"),),
                )
            )
            return None
        typed_elements.append(typed_element)
    if element_type is None:
        raise AssertionError("non-empty list has no element type")
    return TypedListExpression(tuple(typed_elements), ListType(element_type), expression.span)


def _check_match_expression(
    expression: MatchExpression,
    resolution: ResolutionResult,
    symbol_types: list[tuple[SymbolId, DslType]],
    diagnostics: list[Diagnostic],
    record_schemas: tuple[_RecordSchema, ...],
    expected_type: DslType | None,
) -> TypedExpression | None:
    subject = _check_expression(
        expression.subject,
        resolution,
        symbol_types,
        diagnostics,
        record_schemas,
    )
    if subject is None:
        return None
    if not isinstance(subject.type_, OptionType):
        diagnostics.append(
            Diagnostic(
                "E413_INVALID_MATCH_SUBJECT",
                DiagnosticSeverity.ERROR,
                f"cannot match value of type {render_type(subject.type_)}",
                expression.subject.span,
                DiagnosticStage.CHECKER,
            )
        )
        return None
    diagnostic_start = len(diagnostics)
    some_surface: MatchArm | None = None
    none_surface: MatchArm | None = None
    for arm in expression.arms:
        if isinstance(arm.pattern, SomePattern):
            if some_surface is not None:
                diagnostics.append(
                    _duplicate_match_arm(arm.pattern.span, some_surface.pattern.span, "Some")
                )
            else:
                some_surface = arm
        elif isinstance(arm.pattern, NonePattern):
            if none_surface is not None:
                diagnostics.append(
                    _duplicate_match_arm(arm.pattern.span, none_surface.pattern.span, "None")
                )
            else:
                none_surface = arm
        else:
            raise AssertionError("parser produced an unsupported match pattern")
    missing = tuple(
        name for name, arm in (("Some", some_surface), ("None", none_surface)) if arm is None
    )
    if missing:
        diagnostics.append(
            Diagnostic(
                "E415_INCOMPLETE_MATCH",
                DiagnosticSeverity.ERROR,
                f"non-exhaustive Option match; missing {', '.join(missing)}",
                expression.span,
                DiagnosticStage.CHECKER,
            )
        )
    if len(diagnostics) != diagnostic_start or some_surface is None or none_surface is None:
        return None
    some_arm: TypedMatchSomeArm | None = None
    none_arm: TypedMatchNoneArm | None = None
    typed_arms: list[TypedMatchSomeArm | TypedMatchNoneArm] = []
    branch_type: DslType | None = None
    first_body: TypedExpression | None = None
    for arm in expression.arms:
        branch_context = branch_type if branch_type is not None else expected_type
        if isinstance(arm.pattern, SomePattern):
            binding = _binding_for_identifier(
                resolution.bindings,
                arm.pattern.binding.text,
                arm.pattern.binding.span.start.value,
                SymbolKind.MATCH_BINDING,
                None,
            )
            symbol_types.append((binding.symbol_id, subject.type_.element_type))
            body = _check_expression(
                arm.body,
                resolution,
                symbol_types,
                diagnostics,
                record_schemas,
                branch_context,
            )
            if body is None:
                return None
            some_arm = TypedMatchSomeArm(binding.symbol_id, arm.pattern.binding, body, arm.span)
            typed_arms.append(some_arm)
        else:
            body = _check_expression(
                arm.body,
                resolution,
                symbol_types,
                diagnostics,
                record_schemas,
                branch_context,
            )
            if body is None:
                return None
            none_arm = TypedMatchNoneArm(body, arm.span)
            typed_arms.append(none_arm)
        if branch_type is None:
            branch_type = body.type_
            first_body = body
        elif body.type_ != branch_type:
            if first_body is None:
                raise AssertionError("match branch type has no first arm")
            diagnostics.append(
                Diagnostic(
                    "E416_MATCH_BRANCH_TYPE",
                    DiagnosticSeverity.ERROR,
                    "match arms have types "
                    f"{render_type(branch_type)} and {render_type(body.type_)}",
                    body.span,
                    DiagnosticStage.CHECKER,
                    (DiagnosticLabel(first_body.span, "first match arm is here"),),
                )
            )
            return None
    if some_arm is None or none_arm is None or branch_type is None:
        raise AssertionError("exhaustive Option match has missing checked arms")
    return TypedMatchExpression(subject, tuple(typed_arms), branch_type, expression.span)


def _duplicate_match_arm(
    primary_span: SourceSpan,
    first_span: SourceSpan,
    constructor: str,
) -> Diagnostic:
    return Diagnostic(
        "E414_DUPLICATE_MATCH_ARM",
        DiagnosticSeverity.ERROR,
        f"duplicate {constructor} match arm",
        primary_span,
        DiagnosticStage.CHECKER,
        (DiagnosticLabel(first_span, "first arm is here"),),
    )


def _check_record_expression(
    expression: RecordExpression,
    resolution: ResolutionResult,
    symbol_types: list[tuple[SymbolId, DslType]],
    diagnostics: list[Diagnostic],
    record_schemas: tuple[_RecordSchema, ...],
) -> TypedExpression | None:
    schema = _record_schema_for(record_schemas, expression.type_name.text)
    if schema is None:
        diagnostics.append(
            Diagnostic(
                "E406_UNKNOWN_RECORD_TYPE",
                DiagnosticSeverity.ERROR,
                f"unknown record type '{expression.type_name.text}'",
                expression.type_name.span,
                DiagnosticStage.CHECKER,
            )
        )
        return None
    typed_fields: list[TypedRecordField] = []
    supplied_names: list[str] = []
    is_valid = True
    for field in expression.fields:
        expected = _record_field_for(schema, field.name.text)
        value = _check_expression(
            field.value,
            resolution,
            symbol_types,
            diagnostics,
            record_schemas,
            expected.type_ if expected is not None else None,
        )
        if field.name.text in supplied_names:
            diagnostics.append(
                Diagnostic(
                    "E407_DUPLICATE_RECORD_VALUE",
                    DiagnosticSeverity.ERROR,
                    f"record field '{field.name.text}' is supplied more than once",
                    field.name.span,
                    DiagnosticStage.CHECKER,
                )
            )
            is_valid = False
        else:
            supplied_names.append(field.name.text)
        if expected is None:
            diagnostics.append(
                Diagnostic(
                    "E408_UNKNOWN_RECORD_FIELD",
                    DiagnosticSeverity.ERROR,
                    f"record type '{schema.name}' has no field '{field.name.text}'",
                    field.name.span,
                    DiagnosticStage.CHECKER,
                )
            )
            is_valid = False
        elif value is not None and value.type_ != expected.type_:
            diagnostics.append(_type_mismatch(value.span, expected.type_, value.type_))
            is_valid = False
        if value is None:
            is_valid = False
        else:
            typed_fields.append(TypedRecordField(field.name, value, field.span))
    for schema_field in schema.fields:
        if schema_field.name not in supplied_names:
            diagnostics.append(
                Diagnostic(
                    "E409_MISSING_RECORD_FIELD",
                    DiagnosticSeverity.ERROR,
                    f"record type '{schema.name}' requires field '{schema_field.name}'",
                    expression.type_name.span,
                    DiagnosticStage.CHECKER,
                )
            )
            is_valid = False
    if not is_valid:
        return None
    return TypedRecordExpression(
        schema.name,
        tuple(typed_fields),
        NamedType(schema.name),
        expression.span,
    )


def _check_field_access_expression(
    expression: FieldAccessExpression,
    resolution: ResolutionResult,
    symbol_types: list[tuple[SymbolId, DslType]],
    diagnostics: list[Diagnostic],
    record_schemas: tuple[_RecordSchema, ...],
) -> TypedExpression | None:
    record = _check_expression(
        expression.record,
        resolution,
        symbol_types,
        diagnostics,
        record_schemas,
    )
    if record is None:
        return None
    if not isinstance(record.type_, NamedType):
        diagnostics.append(
            Diagnostic(
                "E410_INVALID_FIELD_ACCESS",
                DiagnosticSeverity.ERROR,
                f"cannot access a field of type {render_type(record.type_)}",
                expression.record.span,
                DiagnosticStage.CHECKER,
            )
        )
        return None
    schema = _record_schema_for(record_schemas, record.type_.name)
    if schema is None:
        raise AssertionError("record type annotation has no schema")
    field = _record_field_for(schema, expression.field.text)
    if field is None:
        diagnostics.append(
            Diagnostic(
                "E408_UNKNOWN_RECORD_FIELD",
                DiagnosticSeverity.ERROR,
                f"record type '{schema.name}' has no field '{expression.field.text}'",
                expression.field.span,
                DiagnosticStage.CHECKER,
            )
        )
        return None
    return TypedFieldAccessExpression(record, expression.field, field.type_, expression.span)


def _record_field_for(schema: _RecordSchema, name: str) -> _RecordFieldSchema | None:
    for field in schema.fields:
        if field.name == name:
            return field
    return None


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
