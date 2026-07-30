from __future__ import annotations

from kiwi.dsl.lexer import lex
from kiwi.dsl.names import SymbolKind, resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId


def test_resolver_uses_lexical_bindings_and_canonical_ids() -> None:
    source = SourceFile(
        SourceFileId("names.dtr"),
        "fn helper(x: Int) -> Int = x\n"
        "policy step(view: Int) -> Int = let target = helper(view) in target\n",
    )
    result = resolve(parse(lex(source)).module)

    assert result.diagnostics == ()
    assert tuple(definition.definition_id.value for definition in result.definitions) == (0, 1)
    assert tuple(binding.symbol_id.value for binding in result.bindings) == (0, 1, 2, 3, 4)
    assert tuple(binding.kind for binding in result.bindings) == (
        SymbolKind.DEFINITION,
        SymbolKind.DEFINITION,
        SymbolKind.PARAMETER,
        SymbolKind.PARAMETER,
        SymbolKind.LOCAL,
    )
    assert tuple(reference.symbol_id.value for reference in result.references) == (2, 0, 3, 4)


def test_resolver_reports_stable_recoverable_name_diagnostics() -> None:
    source = SourceFile(
        SourceFileId("errors.dtr"),
        "fn helper(x: Int) -> Int = missing\n"
        "fn helper(x: Int, x: Int) -> Int = helper(x, 1)\n"
        "fn scoped(value: Int) -> Int = let value = 1 in value\n",
    )
    result = resolve(parse(lex(source)).module)

    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E300_DUPLICATE_DEFINITION",
        "E301_UNKNOWN_NAME",
        "E302_DUPLICATE_PARAMETER",
        "E304_INVALID_ARITY",
        "E303_PROHIBITED_SHADOWING",
    )
    duplicate, unknown, duplicate_parameter, arity, shadowing = result.diagnostics
    assert duplicate.primary_span == source.span(ByteOffset(38), ByteOffset(44))
    assert unknown.primary_span == source.span(ByteOffset(27), ByteOffset(34))
    assert duplicate_parameter.primary_span == source.span(ByteOffset(53), ByteOffset(54))
    assert arity.primary_span == source.span(ByteOffset(70), ByteOffset(76))
    assert shadowing.primary_span == source.span(ByteOffset(118), ByteOffset(123))
    assert all(
        diagnostic.secondary_labels
        for diagnostic in (duplicate, duplicate_parameter, arity, shadowing)
    )
