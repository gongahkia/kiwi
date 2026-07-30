from __future__ import annotations

from kiwi.dsl.lexer import lex
from kiwi.dsl.parser import ParserDiagnosticCode, ParseResult, parse
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.syntax import (
    CallExpression,
    FunctionDeclaration,
    GroupExpression,
    IfExpression,
    LetExpression,
    NegateExpression,
    PolicyDeclaration,
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
