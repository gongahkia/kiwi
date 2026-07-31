from __future__ import annotations

from kiwi.dsl.debug import format_surface_module, format_tokens
from kiwi.dsl.lexer import lex
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId


def test_token_debug_output_is_stable_and_source_linked() -> None:
    tokens = lex(SourceFile(SourceFileId("policy.dtr"), "true")).tokens

    assert format_tokens(tokens) == (
        "Token kind=true lexeme='true' value=True span='policy.dtr'@0..4\n"
        "Token kind=end_of_file lexeme='' value=None span='policy.dtr'@4..4"
    )


def test_surface_ast_debug_output_is_stable_and_source_linked() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "fn f() -> Int = 1")
    module = parse(lex(source)).module

    assert (
        format_surface_module(module)
        == """SurfaceModule span='policy.dtr'@0..17
  declarations:
    FunctionDeclaration span='policy.dtr'@0..17
      name:
        Identifier text='f' span='policy.dtr'@3..4
      parameters:
      return_annotation:
        TypeReference span='policy.dtr'@10..13
          name:
            Identifier text='Int' span='policy.dtr'@10..13
      body:
        IntegerLiteral value=1 span='policy.dtr'@16..17"""
    )


def test_surface_ast_debug_output_includes_binary_domain_operations() -> None:
    source = SourceFile(SourceFileId("operators.dtr"), "fn f() -> Bool = 1m + 2m <= 3m")

    rendered = format_surface_module(parse(lex(source)).module)

    assert "BinaryExpression operator=LESS_EQUAL span='operators.dtr'@17..30" in rendered
    assert "BinaryExpression operator=ADD span='operators.dtr'@17..24" in rendered
