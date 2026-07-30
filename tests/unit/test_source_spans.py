from __future__ import annotations

from kiwi.dsl.lexer import LexerDiagnosticCode, lex
from kiwi.dsl.parser import ParserDiagnosticCode, parse
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId, SourcePosition


def test_lexer_multiline_unicode_error_has_exact_byte_and_display_span() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "policy ok() -> Int = 1\n  α\n")

    result = lex(source)

    diagnostic = result.diagnostics[0]
    assert diagnostic.code == LexerDiagnosticCode.INVALID_CHARACTER
    assert diagnostic.primary_span == source.span(ByteOffset(25), ByteOffset(27))
    assert source.positions_of(diagnostic.primary_span) == (
        SourcePosition(ByteOffset(25), line=2, column=3),
        SourcePosition(ByteOffset(27), line=2, column=4),
    )


def test_parser_multiline_error_has_exact_token_span() -> None:
    source = SourceFile(
        SourceFileId("policy.dtr"),
        "policy bad(\n  value Int\n) -> Int = value\n",
    )

    result = parse(lex(source))

    diagnostic = result.diagnostics[0]
    assert diagnostic.code == ParserDiagnosticCode.EXPECTED_TOKEN
    assert diagnostic.primary_span == source.span(ByteOffset(20), ByteOffset(23))
    assert source.positions_of(diagnostic.primary_span) == (
        SourcePosition(ByteOffset(20), line=2, column=9),
        SourcePosition(ByteOffset(23), line=2, column=12),
    )
