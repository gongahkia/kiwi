from __future__ import annotations

from kiwi.dsl.checker import CheckResult, check
from kiwi.dsl.lexer import lex
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.typed_ir import (
    TypedDefinitionKind,
    TypedLetExpression,
    TypedQuantityLiteral,
    TypedStringLiteral,
)
from kiwi.dsl.types import BuiltinType


def test_checker_returns_immutable_typed_surface_module() -> None:
    result = _check(
        "fn helper(x: Int) -> Int = let value = -x in value\n"
        "policy choose(flag: Bool) -> Int = if flag then helper(1) else 2\n"
    )

    assert result.diagnostics == ()
    assert result.module is not None
    helper, choose = result.module.definitions
    assert helper.kind is TypedDefinitionKind.FUNCTION
    assert helper.parameters[0].type_ is BuiltinType.INT
    assert isinstance(helper.body, TypedLetExpression)
    assert helper.body.type_ is BuiltinType.INT
    assert choose.kind is TypedDefinitionKind.POLICY
    assert choose.body.type_ is BuiltinType.INT


def test_checker_reports_type_and_call_diagnostics_with_source_spans() -> None:
    result = _check(
        "fn branch(x: Int) -> Int = if x then false else 1\n"
        "fn caller() -> Int = let value = 1 in value()\n"
    )

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E401_TYPE_MISMATCH",
        "E402_BRANCH_TYPE_MISMATCH",
        "E403_INVALID_CALL",
    )
    assert tuple(diagnostic.primary_span.start.value for diagnostic in result.diagnostics) == (
        30,
        48,
        88,
    )


def test_checker_rejects_unknown_annotation_types() -> None:
    result = _check("fn unknown(x: Missing) -> Int = x\n")

    assert result.module is None
    assert [(diagnostic.code, diagnostic.message) for diagnostic in result.diagnostics] == [
        ("E400_UNKNOWN_TYPE", "unknown type 'Missing'")
    ]


def test_checker_assigns_string_and_quantity_dimension_types() -> None:
    result = _check(
        'fn label() -> String = "alpha"\n'
        "fn wait() -> Duration = 250ms\n"
        "fn aim() -> Angle = 45deg\n"
        "fn chance() -> Probability = 70%\n"
        "fn range() -> Distance = 8m\n"
    )

    assert result.diagnostics == ()
    assert result.module is not None
    assert isinstance(result.module.definitions[0].body, TypedStringLiteral)
    assert tuple(definition.return_type for definition in result.module.definitions) == (
        BuiltinType.STRING,
        BuiltinType.DURATION,
        BuiltinType.ANGLE,
        BuiltinType.PROBABILITY,
        BuiltinType.DISTANCE,
    )
    assert all(
        isinstance(definition.body, TypedQuantityLiteral)
        for definition in result.module.definitions[1:]
    )


def _check(text: str) -> CheckResult:
    source = SourceFile(SourceFileId("types.dtr"), text)
    return check(resolve(parse(lex(source)).module))
