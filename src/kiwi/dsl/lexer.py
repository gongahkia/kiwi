"""Deterministic lexer for the Milestone 1 Kiwi DSL subset."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.quantities import quantity_from_literal
from kiwi.dsl.diagnostics import Diagnostic, DiagnosticSeverity, DiagnosticStage
from kiwi.dsl.runtime_values import MAX_RUNTIME_STRING_BYTES
from kiwi.dsl.source import ByteOffset, SourceFile
from kiwi.dsl.token import Token, TokenKind, TokenValue

MAX_INTEGER_DIGITS = 1_024


class LexerDiagnosticCode(StrEnum):
    """Stable diagnostic codes emitted by :func:`lex`."""

    INVALID_CHARACTER = "E100_INVALID_CHARACTER"
    INTEGER_TOO_LONG = "E101_INTEGER_TOO_LONG"
    UNTERMINATED_STRING = "E102_UNTERMINATED_STRING"
    INVALID_STRING_ESCAPE = "E103_INVALID_STRING_ESCAPE"
    STRING_TOO_LONG = "E104_STRING_TOO_LONG"
    INVALID_QUANTITY_UNIT = "E105_INVALID_QUANTITY_UNIT"
    INVALID_PROBABILITY = "E106_INVALID_PROBABILITY"


@dataclass(frozen=True, slots=True)
class LexResult:
    """Tokens and recoverable diagnostics from one source file."""

    source: SourceFile
    tokens: tuple[Token, ...]
    diagnostics: tuple[Diagnostic, ...]


_KEYWORDS = {
    "policy": TokenKind.POLICY,
    "fn": TokenKind.FN,
    "let": TokenKind.LET,
    "in": TokenKind.IN,
    "if": TokenKind.IF,
    "then": TokenKind.THEN,
    "else": TokenKind.ELSE,
    "true": TokenKind.TRUE,
    "false": TokenKind.FALSE,
    "Some": TokenKind.SOME,
    "None": TokenKind.NONE,
    "type": TokenKind.TYPE,
}
_SINGLE_CHARACTER_TOKENS = {
    ":": TokenKind.COLON,
    ",": TokenKind.COMMA,
    "=": TokenKind.EQUALS,
    "(": TokenKind.LEFT_PAREN,
    ")": TokenKind.RIGHT_PAREN,
    "{": TokenKind.LEFT_BRACE,
    "}": TokenKind.RIGHT_BRACE,
    ".": TokenKind.DOT,
    "<": TokenKind.LEFT_ANGLE,
    ">": TokenKind.RIGHT_ANGLE,
    "-": TokenKind.MINUS,
}


def lex(source: SourceFile) -> LexResult:
    """Tokenise source without executing or interpreting player program semantics."""
    tokens: list[Token] = []
    diagnostics: list[Diagnostic] = []
    cursor = _Cursor(source)
    while not cursor.at_end:
        character = cursor.current
        if character.isspace():
            cursor.advance()
        elif character == "#":
            cursor.skip_comment()
        elif _is_identifier_start(character):
            _lex_identifier_or_keyword(cursor, tokens)
        elif character.isascii() and character.isdecimal():
            _lex_integer(cursor, tokens, diagnostics)
        elif character == '"':
            _lex_string(cursor, tokens, diagnostics)
        elif cursor.starts_with("->"):
            tokens.append(cursor.token(TokenKind.ARROW, 2))
        elif token_kind := _SINGLE_CHARACTER_TOKENS.get(character):
            tokens.append(cursor.token(token_kind, 1))
        else:
            diagnostics.append(
                cursor.diagnostic(
                    LexerDiagnosticCode.INVALID_CHARACTER,
                    f"unexpected character {character!r}",
                    1,
                )
            )
    tokens.append(cursor.token(TokenKind.EOF, 0))
    return LexResult(source, tuple(tokens), tuple(diagnostics))


def _lex_identifier_or_keyword(cursor: _Cursor, tokens: list[Token]) -> None:
    start = cursor.index
    start_offset = cursor.byte_offset
    while not cursor.at_end and _is_identifier_continue(cursor.current):
        cursor.advance()
    lexeme = cursor.text[start : cursor.index]
    kind = _KEYWORDS.get(lexeme, TokenKind.IDENTIFIER)
    value = True if kind is TokenKind.TRUE else False if kind is TokenKind.FALSE else None
    tokens.append(cursor.token_from_start(kind, start, start_offset, value=value))


def _lex_integer(
    cursor: _Cursor,
    tokens: list[Token],
    diagnostics: list[Diagnostic],
) -> None:
    start = cursor.index
    start_offset = cursor.byte_offset
    while not cursor.at_end and cursor.current.isascii() and cursor.current.isdecimal():
        cursor.advance()
    digits = cursor.text[start : cursor.index]
    suffix_start = cursor.index
    if not cursor.at_end and cursor.current == "%":
        cursor.advance()
    elif not cursor.at_end and cursor.current.isascii() and cursor.current.isalpha():
        while not cursor.at_end and cursor.current.isascii() and cursor.current.isalpha():
            cursor.advance()
    suffix = cursor.text[suffix_start : cursor.index]
    if len(digits) > MAX_INTEGER_DIGITS:
        diagnostics.append(
            cursor.diagnostic_from_start(
                LexerDiagnosticCode.INTEGER_TOO_LONG,
                f"integer literal exceeds {MAX_INTEGER_DIGITS} decimal digits",
                start,
                start_offset,
            )
        )
        return
    if suffix:
        try:
            quantity = quantity_from_literal(int(digits), suffix)
        except ValueError as error:
            code = (
                LexerDiagnosticCode.INVALID_PROBABILITY
                if suffix == "%" and int(digits) > 100
                else LexerDiagnosticCode.INVALID_QUANTITY_UNIT
            )
            diagnostics.append(cursor.diagnostic_from_start(code, str(error), start, start_offset))
            return
        tokens.append(
            cursor.token_from_start(TokenKind.QUANTITY, start, start_offset, value=quantity)
        )
        return
    tokens.append(
        cursor.token_from_start(TokenKind.INTEGER, start, start_offset, value=int(digits))
    )


def _lex_string(
    cursor: _Cursor,
    tokens: list[Token],
    diagnostics: list[Diagnostic],
) -> None:
    start = cursor.index
    start_offset = cursor.byte_offset
    cursor.advance()
    value: list[str] = []
    while not cursor.at_end and cursor.current not in {'"', "\n", "\r"}:
        if cursor.current != "\\":
            value.append(cursor.current)
            cursor.advance()
            continue
        escape_start = cursor.index
        escape_offset = cursor.byte_offset
        cursor.advance()
        if cursor.at_end or cursor.current in {"\n", "\r"}:
            diagnostics.append(
                cursor.diagnostic_from_start(
                    LexerDiagnosticCode.UNTERMINATED_STRING,
                    "unterminated string literal",
                    start,
                    start_offset,
                )
            )
            return
        escaped = cursor.current
        decoded = {"\\": "\\", '"': '"', "n": "\n", "r": "\r", "t": "\t"}.get(escaped)
        cursor.advance()
        if decoded is None:
            diagnostics.append(
                cursor.diagnostic_from_start(
                    LexerDiagnosticCode.INVALID_STRING_ESCAPE,
                    f"invalid string escape \\{escaped}",
                    escape_start,
                    escape_offset,
                )
            )
            continue
        value.append(decoded)
    if cursor.at_end or cursor.current != '"':
        diagnostics.append(
            cursor.diagnostic_from_start(
                LexerDiagnosticCode.UNTERMINATED_STRING,
                "unterminated string literal",
                start,
                start_offset,
            )
        )
        return
    cursor.advance()
    decoded_value = "".join(value)
    if len(decoded_value.encode("utf-8")) > MAX_RUNTIME_STRING_BYTES:
        diagnostics.append(
            cursor.diagnostic_from_start(
                LexerDiagnosticCode.STRING_TOO_LONG,
                f"string literal exceeds {MAX_RUNTIME_STRING_BYTES} UTF-8 bytes",
                start,
                start_offset,
            )
        )
        return
    tokens.append(
        cursor.token_from_start(TokenKind.STRING, start, start_offset, value=decoded_value)
    )


def _is_identifier_start(character: str) -> bool:
    return character == "_" or character.isascii() and character.isalpha()


def _is_identifier_continue(character: str) -> bool:
    return _is_identifier_start(character) or character.isascii() and character.isdecimal()


@dataclass(slots=True)
class _Cursor:
    """Mutable local lexer state; it never escapes :func:`lex`."""

    source: SourceFile
    index: int = 0
    byte_offset: int = 0

    @property
    def text(self) -> str:
        """Return the source text currently being lexed."""
        return self.source.text

    @property
    def at_end(self) -> bool:
        """Return whether the cursor reached the end of source."""
        return self.index == len(self.text)

    @property
    def current(self) -> str:
        """Return the current code point when not at end."""
        return self.text[self.index]

    def starts_with(self, prefix: str) -> bool:
        """Return whether the remaining source starts with a prefix."""
        return self.text.startswith(prefix, self.index)

    def advance(self) -> None:
        """Advance over one Unicode code point."""
        self.byte_offset += len(self.current.encode("utf-8"))
        self.index += 1

    def skip_comment(self) -> None:
        """Skip a line comment while preserving the newline for whitespace handling."""
        while not self.at_end and self.current != "\n":
            self.advance()

    def token(self, kind: TokenKind, character_count: int) -> Token:
        """Create a token from the current offset and consume its source text."""
        start = self.index
        start_offset = self.byte_offset
        for _ in range(character_count):
            self.advance()
        return self.token_from_start(kind, start, start_offset)

    def token_from_start(
        self,
        kind: TokenKind,
        start: int,
        start_offset: int,
        value: TokenValue = None,
    ) -> Token:
        """Create a token from an already consumed source range."""
        return Token(
            kind,
            self.text[start : self.index],
            self.source.span(ByteOffset(start_offset), ByteOffset(self.byte_offset)),
            value,
        )

    def diagnostic(self, code: str, message: str, character_count: int) -> Diagnostic:
        """Create a lexer error at the current cursor and consume its range."""
        start = self.index
        start_offset = self.byte_offset
        for _ in range(character_count):
            self.advance()
        return self.diagnostic_from_start(code, message, start, start_offset)

    def diagnostic_from_start(
        self,
        code: str,
        message: str,
        start: int,
        start_offset: int,
    ) -> Diagnostic:
        """Create a lexer error from an already consumed source range."""
        return Diagnostic(
            code,
            DiagnosticSeverity.ERROR,
            message,
            self.source.span(ByteOffset(start_offset), ByteOffset(self.byte_offset)),
            DiagnosticStage.LEXER,
        )
