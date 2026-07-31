from __future__ import annotations

from kiwi.dsl.lexer import lex
from kiwi.dsl.parser import ParserDiagnosticCode, ParseResult, parse
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.syntax import (
    CallExpression,
    FieldAccessExpression,
    FunctionDeclaration,
    FunctionTypeReference,
    GroupExpression,
    IfExpression,
    IntegerLiteral,
    LambdaExpression,
    LetExpression,
    ListExpression,
    NegateExpression,
    NoneExpression,
    PolicyDeclaration,
    QuantityLiteral,
    RecordExpression,
    RecordTypeDeclaration,
    SomeExpression,
    StringLiteral,
    TypeReference,
)


def parse_text(text: str) -> tuple[SourceFile, ParseResult]:
    source = SourceFile(SourceFileId("policy.dtr"), text)
    return source, parse(lex(source))


def test_parser_builds_source_spanned_policy_expression_tree() -> None:
    source, result = parse_text(
        "policy cautious(view: Observation, memory: Memory) -> Decision = "
        "let target = nearest(view) in if true then helper(target) else -7"
    )

    assert result.diagnostics == ()
    declaration = result.module.declarations[0]
    assert isinstance(declaration, PolicyDeclaration)
    assert isinstance(declaration.return_annotation, TypeReference)
    assert declaration.name.text == "cautious"
    assert tuple(parameter.name.text for parameter in declaration.parameters) == ("view", "memory")
    assert declaration.return_annotation.name.text == "Decision"
    assert isinstance(declaration.body, LetExpression)
    assert isinstance(declaration.body.value, CallExpression)
    assert isinstance(declaration.body.body, IfExpression)
    assert isinstance(declaration.body.body.else_branch, NegateExpression)
    assert declaration.span == source.span(ByteOffset(0), ByteOffset(source.line_index.byte_length))


def test_parser_module_span_preserves_leading_comments() -> None:
    source, result = parse_text("# heading\nfn helper(x: Int) -> Int = x\n")

    assert result.diagnostics == ()
    assert result.module.span == source.span(
        ByteOffset(0), ByteOffset(source.line_index.byte_length)
    )


def test_parser_builds_function_calls_and_grouped_arguments() -> None:
    _, result = parse_text("fn helper(x: Int) -> Int = apply((x), -1)")

    assert result.diagnostics == ()
    declaration = result.module.declarations[0]
    assert isinstance(declaration, FunctionDeclaration)
    assert isinstance(declaration.body, CallExpression)
    assert isinstance(declaration.body.arguments[0], GroupExpression)
    assert isinstance(declaration.body.arguments[1], NegateExpression)


def test_parser_combines_lexer_diagnostics_and_recovers_to_later_declarations() -> None:
    source, result = parse_text(
        "oops @ policy one(x: Int) -> Int = x stray fn two(x: Int) -> Int = x"
    )

    assert tuple(type(declaration) for declaration in result.module.declarations) == (
        PolicyDeclaration,
        FunctionDeclaration,
    )
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E100_INVALID_CHARACTER",
        ParserDiagnosticCode.EXPECTED_DECLARATION,
        ParserDiagnosticCode.EXPECTED_DECLARATION,
    )
    assert result.diagnostics[1].primary_span == source.span(ByteOffset(0), ByteOffset(4))
    stray_start = len(b"oops @ policy one(x: Int) -> Int = x ")
    assert result.diagnostics[2].primary_span == source.span(
        ByteOffset(stray_start), ByteOffset(stray_start + len("stray"))
    )


def test_parser_reports_stable_source_linked_expected_token_diagnostics() -> None:
    source, result = parse_text("policy bad(x Int) -> Int = x")

    assert result.module.declarations == ()
    assert len(result.diagnostics) == 1
    diagnostic = result.diagnostics[0]
    assert diagnostic.code == ParserDiagnosticCode.EXPECTED_TOKEN
    assert diagnostic.message == "expected ':'"
    assert diagnostic.primary_span == source.span(ByteOffset(13), ByteOffset(16))


def test_parser_builds_string_and_quantity_literals_with_source_spans() -> None:
    source, result = parse_text('fn label() -> String = "alpha"\nfn wait() -> Duration = 250ms')

    assert result.diagnostics == ()
    label, wait = result.module.declarations
    assert isinstance(label, FunctionDeclaration)
    assert isinstance(label.body, StringLiteral)
    assert label.body.value == "alpha"
    assert isinstance(wait, FunctionDeclaration)
    assert isinstance(wait.body, QuantityLiteral)
    literal_start = source.text.index("250ms")
    assert wait.body.span == source.span(ByteOffset(literal_start), ByteOffset(literal_start + 5))


def test_parser_builds_record_type_construction_and_field_access() -> None:
    source, result = parse_text(
        "type Point = { x: Int, y: Int }\n"
        "fn x(point: Point) -> Int = point.x\n"
        "fn origin() -> Point = Point { y = 0, x = 0 }"
    )

    assert result.diagnostics == ()
    point, x, origin = result.module.declarations
    assert isinstance(point, RecordTypeDeclaration)
    assert tuple(field.name.text for field in point.fields) == ("x", "y")
    assert isinstance(x, FunctionDeclaration)
    assert isinstance(x.body, FieldAccessExpression)
    assert x.body.field.text == "x"
    assert isinstance(origin, FunctionDeclaration)
    assert isinstance(origin.body, RecordExpression)
    assert tuple(field.name.text for field in origin.body.fields) == ("y", "x")


def test_parser_builds_option_types_and_closed_constructors() -> None:
    source, result = parse_text(
        "fn some() -> Option<Int> = Some(1)\nfn none() -> Option<Option<Int>> = None"
    )

    assert result.diagnostics == ()
    some, none = result.module.declarations
    assert isinstance(some, FunctionDeclaration)
    assert isinstance(some.return_annotation, TypeReference)
    assert some.return_annotation.name.text == "Option"
    assert isinstance(some.return_annotation.arguments[0], TypeReference)
    assert some.return_annotation.arguments[0].name.text == "Int"
    assert isinstance(some.body, SomeExpression)
    assert isinstance(none, FunctionDeclaration)
    assert isinstance(none.return_annotation, TypeReference)
    assert isinstance(none.return_annotation.arguments[0], TypeReference)
    assert isinstance(none.return_annotation.arguments[0].arguments[0], TypeReference)
    assert none.return_annotation.arguments[0].arguments[0].name.text == "Int"
    assert isinstance(none.body, NoneExpression)
    assert none.span == source.span(
        ByteOffset(source.text.index("fn none")), ByteOffset(len(source.text))
    )


def test_parser_builds_source_ordered_list_literals() -> None:
    _, result = parse_text("fn values() -> List<Int> = [1, 2]")

    assert result.diagnostics == ()
    declaration = result.module.declarations[0]
    assert isinstance(declaration, FunctionDeclaration)
    assert isinstance(declaration.body, ListExpression)
    first, second = declaration.body.elements
    assert isinstance(first, IntegerLiteral)
    assert isinstance(second, IntegerLiteral)
    assert (first.value, second.value) == (1, 2)


def test_parser_builds_function_types_and_anonymous_functions() -> None:
    _, result = parse_text("fn factory(seed: Int) -> Int -> Int = fn value -> seed")

    assert result.diagnostics == ()
    declaration = result.module.declarations[0]
    assert isinstance(declaration, FunctionDeclaration)
    assert isinstance(declaration.return_annotation, FunctionTypeReference)
    assert isinstance(declaration.return_annotation.parameters[0], TypeReference)
    assert declaration.return_annotation.parameters[0].name.text == "Int"
    assert isinstance(declaration.body, LambdaExpression)
    assert tuple(parameter.text for parameter in declaration.body.parameters) == ("value",)
