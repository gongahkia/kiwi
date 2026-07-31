from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import BuildList, BytecodeHeader
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import (
    MAX_RUNTIME_LIST_ITEMS,
    IntegerValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import VMBudgets, VMFaultCode, run_vm


def test_lists_compile_encode_and_execute_with_contextual_empty_values() -> None:
    source = SourceFile(
        SourceFileId("lists.dtr"),
        "fn values() -> List<Int> = [1, 2]\n"
        "fn empty() -> List<Int> = []\n"
        "fn nested() -> List<List<Int>> = [[1], []]\n"
        "policy options() -> List<Option<Int>> = [Some(1), None]\n",
    )
    parsed = parse(lex(source))
    checked = check(resolve(parsed.module))

    assert parsed.diagnostics == ()
    assert checked.diagnostics == ()
    assert checked.module is not None
    lowered = lower(checked.module)
    assert tuple(entry.span.start.value for entry in lowered.source_map.entries) == tuple(
        sorted(entry.span.start.value for entry in lowered.source_map.entries)
    )
    module = compile_core(lowered.module, BytecodeHeader(source.file_id))
    assert any(
        isinstance(instruction, BuildList)
        for function in module.functions
        for instruction in function.instructions
    )

    assert run_vm(module, FunctionId(0), ()).value == ListValue((IntegerValue(1), IntegerValue(2)))
    assert run_vm(module, FunctionId(1), ()).value == ListValue(())
    assert run_vm(module, FunctionId(2), ()).value == ListValue(
        (ListValue((IntegerValue(1),)), ListValue(()))
    )
    assert run_vm(module, FunctionId(3), ()).value == ListValue(
        (OptionSomeValue(IntegerValue(1)), OptionNoneValue())
    )
    assert decode_bytecode(encode_bytecode(module)) == module


def test_lists_require_a_context_for_empty_values_and_uniform_elements() -> None:
    source = SourceFile(
        SourceFileId("lists-invalid.dtr"),
        "fn empty() -> Int = []\n"
        "fn mixed() -> List<Int> = [1, false]\n"
        "fn none() -> List<Int> = [None]\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E418_AMBIGUOUS_EMPTY_LIST",
        "E419_LIST_ELEMENT_TYPE",
        "E412_AMBIGUOUS_NONE",
    )

    wrong_arity = SourceFile(
        SourceFileId("list-type-invalid.dtr"),
        "fn invalid() -> List<Int, Bool> = []\n",
    )
    arity_result = check(resolve(parse(lex(wrong_arity)).module))

    assert tuple(diagnostic.code for diagnostic in arity_result.diagnostics) == (
        "E417_INVALID_LIST_TYPE",
    )


def test_lists_charge_element_count_plus_container_and_require_version_two() -> None:
    source = SourceFile(SourceFileId("list-budget.dtr"), "fn values() -> List<Int> = [1, 2]\n")
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    exhausted = run_vm(module, FunctionId(0), (), VMBudgets(allocation_limit=2))
    completed = run_vm(module, FunctionId(0), (), VMBudgets(allocation_limit=3))

    assert exhausted.fault is not None
    assert exhausted.fault.code is VMFaultCode.ALLOCATION_BUDGET
    assert completed.value == ListValue((IntegerValue(1), IntegerValue(2)))
    with pytest.raises(ValueError, match="version 1"):
        compile_core(lower(checked.module).module, BytecodeHeader(source.file_id, 1, 1, 1))


def test_lists_reject_literals_above_the_runtime_item_limit() -> None:
    elements = ", ".join("1" for _ in range(MAX_RUNTIME_LIST_ITEMS + 1))
    source = SourceFile(
        SourceFileId("list-limit.dtr"), f"fn values() -> List<Int> = [{elements}]\n"
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == ("E420_LIST_ITEM_LIMIT",)
