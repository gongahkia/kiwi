"""Immutable lexical tokens for the Kiwi DSL surface language."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.quantities import Quantity
from kiwi.dsl.source import SourceSpan

type TokenValue = int | bool | str | Quantity | None


class TokenKind(StrEnum):
    """The fixed token vocabulary for the Milestone 1 surface grammar."""

    EOF = "end_of_file"
    IDENTIFIER = "identifier"
    INTEGER = "integer"
    STRING = "string"
    QUANTITY = "quantity"
    TRUE = "true"
    FALSE = "false"
    SOME = "some"
    NONE = "none"
    TYPE = "type"
    POLICY = "policy"
    FN = "fn"
    LET = "let"
    IN = "in"
    IF = "if"
    THEN = "then"
    ELSE = "else"
    COLON = "colon"
    COMMA = "comma"
    EQUALS = "equals"
    LEFT_PAREN = "left_paren"
    RIGHT_PAREN = "right_paren"
    LEFT_BRACE = "left_brace"
    RIGHT_BRACE = "right_brace"
    DOT = "dot"
    LEFT_ANGLE = "left_angle"
    RIGHT_ANGLE = "right_angle"
    ARROW = "arrow"
    MINUS = "minus"


@dataclass(frozen=True, slots=True)
class Token:
    """One source-linked token with an optional decoded literal value."""

    kind: TokenKind
    lexeme: str
    span: SourceSpan
    value: TokenValue = None

    def __post_init__(self) -> None:
        if not isinstance(self.lexeme, str):
            raise ValueError("token lexeme must be a string")
        if self.kind is TokenKind.INTEGER:
            if not isinstance(self.value, int) or isinstance(self.value, bool):
                raise ValueError("integer token requires an integer value")
        elif self.kind is TokenKind.STRING:
            if not isinstance(self.value, str):
                raise ValueError("string token requires a string value")
        elif self.kind is TokenKind.QUANTITY:
            if not isinstance(self.value, Quantity):
                raise ValueError("quantity token requires a quantity value")
        elif self.kind is TokenKind.TRUE:
            if self.value is not True:
                raise ValueError("true token requires value True")
        elif self.kind is TokenKind.FALSE:
            if self.value is not False:
                raise ValueError("false token requires value False")
        elif self.value is not None:
            raise ValueError("only literal tokens may carry a decoded value")
