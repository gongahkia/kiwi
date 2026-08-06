from __future__ import annotations

from dataclasses import FrozenInstanceError

import pytest

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId, SourceSpan
from kiwi.dsl.syntax import (
    BooleanLiteral,
    CallExpression,
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
    QuantityLiteral,
    StringLiteral,
    SurfaceModule,
    TypeReference,
)
from kiwi.ui.syntax import SourceStyle, SyntaxSpan, syntax_spans


def test_surface_nodes_are_immutable_and_source_spanned() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "fn helper(x: Int) -> Int = x")
    span = source.span(ByteOffset(0), ByteOffset(source.line_index.byte_length))
    name = Identifier("helper", span)
    type_name = Identifier("Int", span)
    type_reference = TypeReference(type_name, span)
    parameter = Parameter(Identifier("x", span), type_reference, span)
    integer = IntegerLiteral(1, span)
    boolean = BooleanLiteral(True, span)
    string = StringLiteral("label", span)
    quantity = QuantityLiteral(Quantity(QuantityDimension.DURATION, ExactRational(1, 4)), span)
    reference = NameExpression(Identifier("x", span), span)
    negate = NegateExpression(integer, span)
    grouped = GroupExpression(reference, span)
    call = CallExpression(reference, (integer, boolean), span)
    binding = LetExpression(Identifier("x", span), integer, reference, span)
    conditional = IfExpression(boolean, reference, integer, span)
    function = FunctionDeclaration(name, (parameter,), type_reference, conditional, span)
    policy = PolicyDeclaration(name, (parameter,), type_reference, binding, span)
    module = SurfaceModule((function, policy), span)

    for node in (
        name,
        type_name,
        type_reference,
        parameter,
        integer,
        boolean,
        string,
        quantity,
        reference,
        negate,
        grouped,
        call,
        binding,
        conditional,
        function,
        policy,
        module,
    ):
        assert node.span == span

    with pytest.raises(FrozenInstanceError):
        module.declarations = ()  # type: ignore[misc]


def test_group_expression_preserves_parenthesis_provenance() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "(x)")
    inner_span = source.span(ByteOffset(1), ByteOffset(2))
    group_span = source.span(ByteOffset(0), ByteOffset(3))
    reference = NameExpression(Identifier("x", inner_span), inner_span)

    grouped = GroupExpression(reference, group_span)

    assert grouped.expression.span == inner_span
    assert grouped.span == group_span


def test_surface_nodes_use_source_spans_not_python_identity() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "x")
    span = source.span(ByteOffset(0), ByteOffset(1))
    first = NameExpression(Identifier("x", span), span)
    second = NameExpression(Identifier("x", span), span)

    assert first == second
    assert first.span == SourceSpan(SourceFileId("policy.dtr"), ByteOffset(0), ByteOffset(1))


def test_syntax_spans_preserve_lexer_token_and_error_source_ranges() -> None:
    source = SourceFile(
        SourceFileId("styled.dtr"),
        'fn choose(flag: Bool) -> String = if flag then "yes" else 0 @ α',
    )

    styled = syntax_spans(source)

    assert tuple((_span_text(source, item), item.style) for item in styled) == (
        ("fn", SourceStyle.KEYWORD),
        ("choose", SourceStyle.IDENTIFIER),
        ("(", SourceStyle.PUNCTUATION),
        ("flag", SourceStyle.IDENTIFIER),
        (":", SourceStyle.PUNCTUATION),
        ("Bool", SourceStyle.IDENTIFIER),
        (")", SourceStyle.PUNCTUATION),
        ("->", SourceStyle.OPERATOR),
        ("String", SourceStyle.IDENTIFIER),
        ("=", SourceStyle.OPERATOR),
        ("if", SourceStyle.KEYWORD),
        ("flag", SourceStyle.IDENTIFIER),
        ("then", SourceStyle.KEYWORD),
        ('"yes"', SourceStyle.LITERAL),
        ("else", SourceStyle.KEYWORD),
        ("0", SourceStyle.LITERAL),
        ("@", SourceStyle.INVALID),
        ("α", SourceStyle.INVALID),
    )
    assert all(item.span.file_id == source.file_id for item in styled)


def _span_text(source: SourceFile, styled: SyntaxSpan) -> str:
    span = styled.span
    return source.text.encode("utf-8")[span.start.value : span.end.value].decode("utf-8")
