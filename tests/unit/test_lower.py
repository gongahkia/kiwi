from __future__ import annotations

import pytest

from kiwi.dsl.checker import check
from kiwi.dsl.ids import ExpressionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import LowerResult, SourceMap, SourceMapEntry, lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId


def test_lowering_assigns_preorder_expression_ids_and_source_maps() -> None:
    source = SourceFile(
        SourceFileId("lower.dtr"),
        "fn helper(x: Int) -> Int = let value = -x in value\n"
        "policy choose(flag: Bool) -> Int = if flag then helper(1) else 2\n",
    )
    first = _lower(source)
    second = _lower(source)

    assert first == second
    assert tuple(entry.expression_id.value for entry in first.source_map.entries) == tuple(
        range(10)
    )
    assert tuple(entry.definition_id.value for entry in first.source_map.entries) == (
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        1,
        1,
        1,
    )
    call_start = source.text.index("helper(1)")
    assert first.source_map.entry_for(ExpressionId(6)).span == source.span(
        ByteOffset(call_start),
        ByteOffset(call_start + len("helper(1)")),
    )


def test_source_map_rejects_noncanonical_expression_ids() -> None:
    source = SourceFile(SourceFileId("lower.dtr"), "fn value() -> Int = 1")
    result = _lower(source)

    assert result.source_map.entry_for(ExpressionId(0)).expression_id == ExpressionId(0)
    with pytest.raises(ValueError, match="contiguous"):
        SourceMap(
            (
                SourceMapEntry(
                    ExpressionId(1),
                    result.source_map.entries[0].definition_id,
                    source.span(ByteOffset(0), ByteOffset(len(source.text))),
                ),
            )
        )


def _lower(source: SourceFile) -> LowerResult:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    assert checked.diagnostics == ()
    return lower(checked.module)
