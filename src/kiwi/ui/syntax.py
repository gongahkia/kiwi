"""Headless syntax-style spans derived from source-linked DSL lexer output."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.dsl.lexer import lex
from kiwi.dsl.source import SourceFile, SourceSpan
from kiwi.dsl.token import TokenKind


class SourceStyle(StrEnum):
    """The compact fixed source styles supported by the MVP workbench."""

    DEFAULT = "default"
    KEYWORD = "keyword"
    LITERAL = "literal"
    IDENTIFIER = "identifier"
    OPERATOR = "operator"
    PUNCTUATION = "punctuation"
    INVALID = "invalid"


@dataclass(frozen=True, slots=True)
class SyntaxSpan:
    """One source-provenance-preserving lexical styling range."""

    span: SourceSpan
    style: SourceStyle

    def __post_init__(self) -> None:
        if not isinstance(self.span, SourceSpan):
            raise TypeError("syntax span requires a source span")
        if not isinstance(self.style, SourceStyle):
            raise TypeError("syntax span requires a source style")
        if self.span.byte_length == 0:
            raise ValueError("syntax span must not be empty")


_KEYWORDS = frozenset(
    (
        TokenKind.POLICY,
        TokenKind.FN,
        TokenKind.LET,
        TokenKind.IN,
        TokenKind.IF,
        TokenKind.THEN,
        TokenKind.ELSE,
        TokenKind.MATCH,
        TokenKind.WITH,
        TokenKind.TYPE,
    )
)
_LITERALS = frozenset(
    (
        TokenKind.INTEGER,
        TokenKind.STRING,
        TokenKind.QUANTITY,
        TokenKind.TRUE,
        TokenKind.FALSE,
        TokenKind.SOME,
        TokenKind.NONE,
    )
)
_OPERATORS = frozenset(
    (
        TokenKind.EQUALS,
        TokenKind.PIPE,
        TokenKind.LESS_EQUAL,
        TokenKind.GREATER_EQUAL,
        TokenKind.ARROW,
        TokenKind.PLUS,
        TokenKind.MINUS,
        TokenKind.LEFT_ANGLE,
        TokenKind.RIGHT_ANGLE,
    )
)


def syntax_spans(source: SourceFile) -> tuple[SyntaxSpan, ...]:
    """Return token and lexer-error style spans in canonical source-byte order."""
    if not isinstance(source, SourceFile):
        raise TypeError("syntax styling requires a source file")
    lexed = lex(source)
    spans = [
        SyntaxSpan(token.span, _style_for_token(token.kind))
        for token in lexed.tokens
        if token.kind is not TokenKind.EOF
    ]
    spans.extend(
        SyntaxSpan(diagnostic.primary_span, SourceStyle.INVALID) for diagnostic in lexed.diagnostics
    )
    return tuple(sorted(spans, key=lambda item: (item.span.start.value, item.span.end.value)))


def _style_for_token(kind: TokenKind) -> SourceStyle:
    if kind in _KEYWORDS:
        return SourceStyle.KEYWORD
    if kind in _LITERALS:
        return SourceStyle.LITERAL
    if kind is TokenKind.IDENTIFIER:
        return SourceStyle.IDENTIFIER
    if kind in _OPERATORS:
        return SourceStyle.OPERATOR
    return SourceStyle.PUNCTUATION
