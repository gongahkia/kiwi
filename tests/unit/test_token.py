from __future__ import annotations

from dataclasses import FrozenInstanceError

import pytest

from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.token import Token, TokenKind


def test_tokens_keep_kind_lexeme_value_and_source_span() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "42 true policy")
    integer = Token(TokenKind.INTEGER, "42", source.span(ByteOffset(0), ByteOffset(2)), value=42)
    boolean = Token(TokenKind.TRUE, "true", source.span(ByteOffset(3), ByteOffset(7)), value=True)
    keyword = Token(TokenKind.POLICY, "policy", source.span(ByteOffset(8), ByteOffset(14)))

    assert integer.kind is TokenKind.INTEGER
    assert integer.value == 42
    assert boolean.value is True
    assert keyword.value is None
    assert keyword.span.file_id == SourceFileId("policy.dtr")


def test_tokens_are_immutable() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "x")
    token = Token(TokenKind.IDENTIFIER, "x", source.span(ByteOffset(0), ByteOffset(1)))

    with pytest.raises(FrozenInstanceError):
        token.lexeme = "y"  # type: ignore[misc]


@pytest.mark.parametrize(
    ("kind", "lexeme", "value", "message"),
    (
        (TokenKind.INTEGER, "42", None, "integer token"),
        (TokenKind.INTEGER, "42", True, "integer token"),
        (TokenKind.TRUE, "true", None, "true token"),
        (TokenKind.FALSE, "false", True, "false token"),
        (TokenKind.IDENTIFIER, "name", 1, "only literal"),
    ),
)
def test_tokens_reject_invalid_decoded_values(
    kind: TokenKind,
    lexeme: str,
    value: int | bool | None,
    message: str,
) -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "token")

    with pytest.raises(ValueError, match=message):
        Token(kind, lexeme, source.span(ByteOffset(0), ByteOffset(1)), value=value)


def test_token_kind_covers_the_milestone_one_grammar() -> None:
    assert tuple(TokenKind) == (
        TokenKind.EOF,
        TokenKind.IDENTIFIER,
        TokenKind.INTEGER,
        TokenKind.TRUE,
        TokenKind.FALSE,
        TokenKind.POLICY,
        TokenKind.FN,
        TokenKind.LET,
        TokenKind.IN,
        TokenKind.IF,
        TokenKind.THEN,
        TokenKind.ELSE,
        TokenKind.COLON,
        TokenKind.COMMA,
        TokenKind.EQUALS,
        TokenKind.LEFT_PAREN,
        TokenKind.RIGHT_PAREN,
        TokenKind.ARROW,
        TokenKind.MINUS,
    )
