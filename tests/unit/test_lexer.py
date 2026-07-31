from __future__ import annotations

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.lexer import MAX_INTEGER_DIGITS, LexerDiagnosticCode, lex
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.token import TokenKind


def test_lexer_emits_milestone_one_tokens_and_ignores_comments() -> None:
    source = SourceFile(
        SourceFileId("policy.dtr"),
        "# heading\npolicy cautious(view: Observation, memory: Memory) -> Decision =\n"
        "  let score = -42\n  if true then helper(score) else false\n",
    )

    result = lex(source)

    assert tuple(token.kind for token in result.tokens) == (
        TokenKind.POLICY,
        TokenKind.IDENTIFIER,
        TokenKind.LEFT_PAREN,
        TokenKind.IDENTIFIER,
        TokenKind.COLON,
        TokenKind.IDENTIFIER,
        TokenKind.COMMA,
        TokenKind.IDENTIFIER,
        TokenKind.COLON,
        TokenKind.IDENTIFIER,
        TokenKind.RIGHT_PAREN,
        TokenKind.ARROW,
        TokenKind.IDENTIFIER,
        TokenKind.EQUALS,
        TokenKind.LET,
        TokenKind.IDENTIFIER,
        TokenKind.EQUALS,
        TokenKind.MINUS,
        TokenKind.INTEGER,
        TokenKind.IF,
        TokenKind.TRUE,
        TokenKind.THEN,
        TokenKind.IDENTIFIER,
        TokenKind.LEFT_PAREN,
        TokenKind.IDENTIFIER,
        TokenKind.RIGHT_PAREN,
        TokenKind.ELSE,
        TokenKind.FALSE,
        TokenKind.EOF,
    )
    assert result.tokens[18].value == 42
    assert result.tokens[20].value is True
    assert result.tokens[27].value is False
    assert result.tokens[-1].span == source.span(
        ByteOffset(source.line_index.byte_length), ByteOffset(source.line_index.byte_length)
    )
    assert result.diagnostics == ()


def test_lexer_recovers_after_invalid_ascii_and_unicode_characters() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "x @ α y")

    result = lex(source)

    assert tuple(token.lexeme for token in result.tokens) == ("x", "y", "")
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        LexerDiagnosticCode.INVALID_CHARACTER,
        LexerDiagnosticCode.INVALID_CHARACTER,
    )
    assert result.diagnostics[0].primary_span == source.span(ByteOffset(2), ByteOffset(3))
    assert result.diagnostics[1].primary_span == source.span(ByteOffset(4), ByteOffset(6))


def test_lexer_recovery_preserves_the_token_after_an_invalid_character() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "@name")

    result = lex(source)

    assert tuple(token.lexeme for token in result.tokens) == ("name", "")


def test_lexer_recognises_function_and_let_scope_keywords() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "fn helper let value = 1 in value")

    result = lex(source)

    assert tuple(token.kind for token in result.tokens) == (
        TokenKind.FN,
        TokenKind.IDENTIFIER,
        TokenKind.LET,
        TokenKind.IDENTIFIER,
        TokenKind.EQUALS,
        TokenKind.INTEGER,
        TokenKind.IN,
        TokenKind.IDENTIFIER,
        TokenKind.EOF,
    )


def test_lexer_recognises_closed_option_match_keywords_and_arm_marker() -> None:
    source = SourceFile(SourceFileId("matching.dtr"), "match value with | Some(item) -> item")

    result = lex(source)

    assert tuple(token.kind for token in result.tokens) == (
        TokenKind.MATCH,
        TokenKind.IDENTIFIER,
        TokenKind.WITH,
        TokenKind.BAR,
        TokenKind.SOME,
        TokenKind.LEFT_PAREN,
        TokenKind.IDENTIFIER,
        TokenKind.RIGHT_PAREN,
        TokenKind.ARROW,
        TokenKind.IDENTIFIER,
        TokenKind.EOF,
    )


def test_lexer_recovers_after_an_oversized_integer_literal() -> None:
    digits = "1" * (MAX_INTEGER_DIGITS + 1)
    source = SourceFile(SourceFileId("policy.dtr"), f"{digits} true")

    result = lex(source)

    assert tuple(token.kind for token in result.tokens) == (TokenKind.TRUE, TokenKind.EOF)
    assert result.diagnostics[0].code == LexerDiagnosticCode.INTEGER_TOO_LONG
    assert result.diagnostics[0].primary_span == source.span(ByteOffset(0), ByteOffset(len(digits)))


def test_lexer_decodes_strings_and_normalizes_exact_quantity_literals() -> None:
    source = SourceFile(
        SourceFileId("literals.dtr"),
        '"alpha\\n\\"beta\\"" 250ms 3s 8m 45deg 70%',
    )

    result = lex(source)

    assert tuple(token.kind for token in result.tokens) == (
        TokenKind.STRING,
        TokenKind.QUANTITY,
        TokenKind.QUANTITY,
        TokenKind.QUANTITY,
        TokenKind.QUANTITY,
        TokenKind.QUANTITY,
        TokenKind.EOF,
    )
    assert result.tokens[0].value == 'alpha\n"beta"'
    assert result.tokens[1].value == Quantity(QuantityDimension.DURATION, ExactRational(1, 4))
    assert result.tokens[2].value == Quantity(QuantityDimension.DURATION, ExactRational(3, 1))
    assert result.tokens[3].value == Quantity(QuantityDimension.DISTANCE, ExactRational(8, 1))
    assert result.tokens[4].value == Quantity(QuantityDimension.ANGLE, ExactRational(1, 8))
    assert result.tokens[5].value == Quantity(QuantityDimension.PROBABILITY, ExactRational(7, 10))
    assert result.diagnostics == ()


def test_lexer_reports_recoverable_string_and_quantity_diagnostics() -> None:
    source = SourceFile(SourceFileId("literals.dtr"), '"bad\\q" 101% 2km "open\ntrue')

    result = lex(source)

    assert tuple(token.kind for token in result.tokens) == (
        TokenKind.STRING,
        TokenKind.TRUE,
        TokenKind.EOF,
    )
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        LexerDiagnosticCode.INVALID_STRING_ESCAPE,
        LexerDiagnosticCode.INVALID_PROBABILITY,
        LexerDiagnosticCode.INVALID_QUANTITY_UNIT,
        LexerDiagnosticCode.UNTERMINATED_STRING,
    )
