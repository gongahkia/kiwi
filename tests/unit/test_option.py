from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import BuildSome, BytecodeHeader, PushNone
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import (
    BooleanValue,
    IntegerValue,
    OptionNoneValue,
    OptionSomeValue,
    RecordValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import VMBudgets, VMFaultCode, run_vm


def test_options_compile_encode_and_execute_with_contextual_none() -> None:
    source = SourceFile(
        SourceFileId("option.dtr"),
        "type Memory = { target: Option<Int> }\n"
        "fn pass(value: Option<Int>) -> Option<Int> = value\n"
        "fn some() -> Option<Int> = Some(1)\n"
        "fn none() -> Option<Int> = None\n"
        "fn branch(flag: Bool) -> Option<Int> = if flag then Some(2) else None\n"
        "fn memory() -> Memory = Memory { target = None }\n"
        "policy through() -> Option<Int> = pass(None)\n",
    )
    parsed = parse(lex(source))
    checked = check(resolve(parsed.module))

    assert parsed.diagnostics == ()
    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    assert any(
        isinstance(instruction, BuildSome)
        for function in module.functions
        for instruction in function.instructions
    )
    assert any(
        isinstance(instruction, PushNone)
        for function in module.functions
        for instruction in function.instructions
    )

    assert run_vm(module, FunctionId(1), ()).value == OptionSomeValue(IntegerValue(1))
    assert run_vm(module, FunctionId(2), ()).value == OptionNoneValue()
    assert run_vm(module, FunctionId(3), (BooleanValue(True),)).value == OptionSomeValue(
        IntegerValue(2)
    )
    assert run_vm(module, FunctionId(3), (BooleanValue(False),)).value == OptionNoneValue()
    assert run_vm(module, FunctionId(4), ()).value == RecordValue(
        "Memory", ("target",), (OptionNoneValue(),)
    )
    assert run_vm(module, FunctionId(5), ()).value == OptionNoneValue()
    assert decode_bytecode(encode_bytecode(module)) == module


def test_options_require_a_context_and_an_exact_type_argument() -> None:
    source = SourceFile(
        SourceFileId("option-invalid.dtr"),
        "fn bare() -> Int = None\n"
        "fn wrong() -> Option<Int> = Some(true)\n"
        "fn arity() -> Option<Int, Bool> = None\n"
        "fn local() -> Option<Int> = let missing = None in Some(missing)\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E411_INVALID_OPTION_TYPE",
    )

    focused_source = SourceFile(
        SourceFileId("option-context.dtr"),
        "fn bare() -> Int = None\n"
        "fn wrong() -> Option<Int> = Some(true)\n"
        "fn local() -> Option<Int> = let missing = None in Some(missing)\n",
    )
    focused_result = check(resolve(parse(lex(focused_source)).module))

    assert focused_result.module is None
    assert tuple(diagnostic.code for diagnostic in focused_result.diagnostics) == (
        "E412_AMBIGUOUS_NONE",
        "E401_TYPE_MISMATCH",
        "E412_AMBIGUOUS_NONE",
    )


def test_options_consume_vm_allocation_budget_and_require_version_two() -> None:
    source = SourceFile(
        SourceFileId("option-budget.dtr"),
        "fn some() -> Option<Int> = Some(1)\nfn none() -> Option<Int> = None\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    modern_module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    some = run_vm(modern_module, FunctionId(0), (), VMBudgets(allocation_limit=0))
    none = run_vm(modern_module, FunctionId(1), (), VMBudgets(allocation_limit=0))

    assert some.fault is not None
    assert some.fault.code is VMFaultCode.ALLOCATION_BUDGET
    assert none.fault is not None
    assert none.fault.code is VMFaultCode.ALLOCATION_BUDGET
    with pytest.raises(ValueError, match="version 1"):
        compile_core(lower(checked.module).module, BytecodeHeader(source.file_id, 1, 1, 1))
