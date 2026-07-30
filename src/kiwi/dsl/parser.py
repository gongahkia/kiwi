"""Recursive-descent parser for the Milestone 1 Kiwi DSL subset."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum

from kiwi.dsl.diagnostics import Diagnostic, DiagnosticSeverity, DiagnosticStage
from kiwi.dsl.lexer import LexResult
from kiwi.dsl.source import ByteOffset, SourceFile, SourceSpan
from kiwi.dsl.syntax import (
    BooleanLiteral,
    CallExpression,
    Declaration,
    Expression,
    FunctionDeclaration,
    GroupExpression,
    Identifier,
    IfExpression,
    IntegerLiteral,
    LetExpression,
    NameExpression,
    NegateExpression,
    Parameter,
    PolicyDeclaration,
    SurfaceModule,
    TypeReference,
)
from kiwi.dsl.token import Token, TokenKind


class ParserDiagnosticCode(StrEnum):
    """Stable diagnostic codes emitted by :func:`parse`."""

    EXPECTED_DECLARATION = "E200_EXPECTED_DECLARATION"
    EXPECTED_TOKEN = "E201_EXPECTED_TOKEN"
    EXPECTED_EXPRESSION = "E202_EXPECTED_EXPRESSION"


@dataclass(frozen=True, slots=True)
class ParseResult:
    """A partial surface module and all lexer/parser diagnostics."""

    module: SurfaceModule
    diagnostics: tuple[Diagnostic, ...]


def parse(lex_result: LexResult) -> ParseResult:
    """Parse lexer output without evaluating any player-authored program."""
    parser = _Parser(lex_result.source, lex_result.tokens, list(lex_result.diagnostics))
    return ParseResult(parser.parse_module(), tuple(parser.diagnostics))


@dataclass(slots=True)
class _Parser:
    """Mutable parser state retained only during one parse operation."""

    source: SourceFile
    tokens: tuple[Token, ...]
    diagnostics: list[Diagnostic] = field(default_factory=list)
    index: int = 0

    @property
    def current(self) -> Token:
        """Return the current token."""
        return self.tokens[self.index]

    @property
    def at_end(self) -> bool:
        """Return whether the parser reached its EOF token."""
        return self.current.kind is TokenKind.EOF

    def parse_module(self) -> SurfaceModule:
        """Parse zero or more top-level declarations."""
        declarations: list[Declaration] = []
        while not self.at_end:
            if self.current.kind in {TokenKind.POLICY, TokenKind.FN}:
                declaration = self.parse_declaration()
                if declaration is not None:
                    declarations.append(declaration)
                else:
                    self.synchronise_declaration()
            else:
                self.error(
                    ParserDiagnosticCode.EXPECTED_DECLARATION,
                    "expected a 'policy' or 'fn' declaration",
                )
                self.synchronise_declaration()
        return SurfaceModule(
            tuple(declarations),
            self.source.span(ByteOffset(0), ByteOffset(self.source.line_index.byte_length)),
        )

    def parse_declaration(self) -> Declaration | None:
        """Parse one policy or named-function declaration."""
        keyword = self.advance()
        name = self.parse_identifier()
        if name is None:
            return None
        if self.expect(TokenKind.LEFT_PAREN, "'('") is None:
            return None
        parameters = self.parse_parameters()
        if parameters is None:
            return None
        if self.expect(TokenKind.RIGHT_PAREN, "')'") is None:
            return None
        if self.expect(TokenKind.ARROW, "'->'") is None:
            return None
        return_annotation = self.parse_type_reference()
        if return_annotation is None:
            return None
        if self.expect(TokenKind.EQUALS, "'='") is None:
            return None
        body = self.parse_expression()
        if body is None:
            return None
        span = _join_spans(keyword.span, body.span)
        if keyword.kind is TokenKind.POLICY:
            return PolicyDeclaration(name, parameters, return_annotation, body, span)
        return FunctionDeclaration(name, parameters, return_annotation, body, span)

    def parse_parameters(self) -> tuple[Parameter, ...] | None:
        """Parse a comma-separated parameter list without its delimiters."""
        parameters: list[Parameter] = []
        if self.current.kind is TokenKind.RIGHT_PAREN:
            return ()
        while True:
            parameter = self.parse_parameter()
            if parameter is None:
                return None
            parameters.append(parameter)
            if not self.match(TokenKind.COMMA):
                return tuple(parameters)

    def parse_parameter(self) -> Parameter | None:
        """Parse one `name: Type` parameter."""
        name = self.parse_identifier()
        if name is None:
            return None
        if self.expect(TokenKind.COLON, "':'") is None:
            return None
        annotation = self.parse_type_reference()
        if annotation is None:
            return None
        return Parameter(name, annotation, _join_spans(name.span, annotation.span))

    def parse_type_reference(self) -> TypeReference | None:
        """Parse one named type annotation."""
        name = self.parse_identifier()
        if name is None:
            return None
        return TypeReference(name, name.span)

    def parse_expression(self) -> Expression | None:
        """Parse one expression at the M1 expression precedence levels."""
        if self.current.kind is TokenKind.LET:
            return self.parse_let_expression()
        if self.current.kind is TokenKind.IF:
            return self.parse_if_expression()
        return self.parse_application_expression()

    def parse_let_expression(self) -> LetExpression | None:
        """Parse `let name = value in body`."""
        keyword = self.advance()
        name = self.parse_identifier()
        if name is None:
            return None
        if self.expect(TokenKind.EQUALS, "'='") is None:
            return None
        value = self.parse_expression()
        if value is None:
            return None
        if self.expect(TokenKind.IN, "'in'") is None:
            return None
        body = self.parse_expression()
        if body is None:
            return None
        return LetExpression(name, value, body, _join_spans(keyword.span, body.span))

    def parse_if_expression(self) -> IfExpression | None:
        """Parse `if condition then branch else branch`."""
        keyword = self.advance()
        condition = self.parse_expression()
        if condition is None:
            return None
        if self.expect(TokenKind.THEN, "'then'") is None:
            return None
        then_branch = self.parse_expression()
        if then_branch is None:
            return None
        if self.expect(TokenKind.ELSE, "'else'") is None:
            return None
        else_branch = self.parse_expression()
        if else_branch is None:
            return None
        return IfExpression(
            condition, then_branch, else_branch, _join_spans(keyword.span, else_branch.span)
        )

    def parse_application_expression(self) -> Expression | None:
        """Parse left-associative postfix function applications."""
        expression = self.parse_unary_expression()
        if expression is None:
            return None
        while self.match(TokenKind.LEFT_PAREN):
            arguments = self.parse_arguments()
            if arguments is None:
                return None
            closing = self.expect(TokenKind.RIGHT_PAREN, "')'")
            if closing is None:
                return None
            expression = CallExpression(
                expression,
                arguments,
                _join_spans(expression.span, closing.span),
            )
        return expression

    def parse_arguments(self) -> tuple[Expression, ...] | None:
        """Parse a comma-separated argument list without its delimiters."""
        arguments: list[Expression] = []
        if self.current.kind is TokenKind.RIGHT_PAREN:
            return ()
        while True:
            argument = self.parse_expression()
            if argument is None:
                return None
            arguments.append(argument)
            if not self.match(TokenKind.COMMA):
                return tuple(arguments)

    def parse_unary_expression(self) -> Expression | None:
        """Parse unary negation before postfix application."""
        if self.current.kind is TokenKind.MINUS:
            minus = self.advance()
            operand = self.parse_unary_expression()
            if operand is None:
                return None
            return NegateExpression(operand, _join_spans(minus.span, operand.span))
        return self.parse_primary_expression()

    def parse_primary_expression(self) -> Expression | None:
        """Parse literal, name, or parenthesised primary expression."""
        token = self.current
        if token.kind is TokenKind.INTEGER:
            self.advance()
            if isinstance(token.value, int) and not isinstance(token.value, bool):
                return IntegerLiteral(token.value, token.span)
        elif token.kind is TokenKind.TRUE:
            self.advance()
            return BooleanLiteral(True, token.span)
        elif token.kind is TokenKind.FALSE:
            self.advance()
            return BooleanLiteral(False, token.span)
        elif token.kind is TokenKind.IDENTIFIER:
            name = self.parse_identifier()
            if name is not None:
                return NameExpression(name, name.span)
        elif token.kind is TokenKind.LEFT_PAREN:
            opening = self.advance()
            expression = self.parse_expression()
            if expression is None:
                return None
            closing = self.expect(TokenKind.RIGHT_PAREN, "')'")
            if closing is None:
                return None
            return GroupExpression(expression, _join_spans(opening.span, closing.span))
        self.error(ParserDiagnosticCode.EXPECTED_EXPRESSION, "expected an expression")
        return None

    def parse_identifier(self) -> Identifier | None:
        """Parse one identifier in value or type position."""
        token = self.expect(TokenKind.IDENTIFIER, "an identifier")
        if token is None:
            return None
        return Identifier(token.lexeme, token.span)

    def expect(self, kind: TokenKind, expected: str) -> Token | None:
        """Consume an expected token or record a source-linked diagnostic."""
        if self.current.kind is kind:
            return self.advance()
        self.error(ParserDiagnosticCode.EXPECTED_TOKEN, f"expected {expected}")
        return None

    def match(self, kind: TokenKind) -> bool:
        """Consume a token only when its kind matches."""
        if self.current.kind is not kind:
            return False
        self.advance()
        return True

    def advance(self) -> Token:
        """Consume and return the current non-EOF token."""
        token = self.current
        if not self.at_end:
            self.index += 1
        return token

    def synchronise_declaration(self) -> None:
        """Discard malformed declaration input until a stable top-level boundary."""
        while not self.at_end and self.current.kind not in {TokenKind.POLICY, TokenKind.FN}:
            self.advance()

    def error(self, code: ParserDiagnosticCode, message: str) -> None:
        """Append one parser error at the current token span."""
        self.diagnostics.append(
            Diagnostic(
                code,
                DiagnosticSeverity.ERROR,
                message,
                self.current.span,
                DiagnosticStage.PARSER,
            )
        )


def _join_spans(start: SourceSpan, end: SourceSpan) -> SourceSpan:
    """Return the covering source span for two spans in the same source file."""
    if start.file_id != end.file_id:
        raise ValueError("cannot join spans from different source files")
    return SourceSpan(start.file_id, start.start, end.end)
