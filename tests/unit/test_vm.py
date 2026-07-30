from __future__ import annotations

from dataclasses import replace

from kiwi.dsl.bytecode import (
    BytecodeHeader,
    BytecodeModule,
    BytecodeSourceMap,
    InstructionIndex,
    InstructionSourceMapEntry,
    Return,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import BooleanValue, IntegerValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import VMBudgets, VMFaultCode, run_vm, run_vm_with_fallback


def test_vm_executes_calls_frames_slots_and_conditionals_deterministically() -> None:
    source = SourceFile(
        SourceFileId("vm.dtr"),
        "fn identity(x: Int) -> Int = let value = x in value\n"
        "policy choose(flag: Bool) -> Int = if flag then identity(1) else 2\n",
    )
    compiled = _compiled(source)

    first = run_vm(compiled, FunctionId(1), (BooleanValue(True),))
    second = run_vm(compiled, FunctionId(1), (BooleanValue(True),))
    false_branch = run_vm(compiled, FunctionId(1), (BooleanValue(False),))

    assert first == second == run_vm(compiled, FunctionId(1), (BooleanValue(True),))
    assert first.value == IntegerValue(1)
    assert first.fault is None
    assert false_branch.value == IntegerValue(2)
    assert false_branch.fault is None


def test_vm_budgets_and_fallback_are_deterministic() -> None:
    source = SourceFile(
        SourceFileId("budget.dtr"),
        "fn identity(x: Int) -> Int = x\n"
        "policy choose(flag: Bool) -> Int = if flag then identity(1) else 2\n",
    )
    compiled = _compiled(source)

    instruction_fault = run_vm(
        compiled,
        FunctionId(1),
        (BooleanValue(True),),
        VMBudgets(instruction_limit=2),
    )
    allocation_fault = run_vm(
        compiled,
        FunctionId(1),
        (BooleanValue(True),),
        VMBudgets(allocation_limit=0),
    )
    depth_fault = run_vm(
        compiled,
        FunctionId(1),
        (BooleanValue(True),),
        VMBudgets(call_depth_limit=1),
    )
    fallback = run_vm_with_fallback(
        compiled,
        FunctionId(1),
        (BooleanValue(True),),
        IntegerValue(0),
        VMBudgets(instruction_limit=2),
    )

    assert instruction_fault.fault is not None
    assert instruction_fault.fault.code is VMFaultCode.INSTRUCTION_BUDGET
    assert allocation_fault.fault is not None
    assert allocation_fault.fault.code is VMFaultCode.ALLOCATION_BUDGET
    assert depth_fault.fault is not None
    assert depth_fault.fault.code is VMFaultCode.CALL_DEPTH_BUDGET
    assert fallback.value == IntegerValue(0)
    assert fallback.fault == instruction_fault.fault


def test_vm_rejects_invalid_bytecode_without_executing_it() -> None:
    source = SourceFile(SourceFileId("invalid-vm.dtr"), "fn value() -> Int = 1")
    compiled = _compiled(source)
    invalid = replace(
        compiled,
        functions=(replace(compiled.functions[0], instructions=(Return(),)),),
        source_map=_source_map_for(compiled, 1),
    )

    result = run_vm(invalid, FunctionId(0), ())

    assert result.value is None
    assert result.fault is not None
    assert result.fault.code is VMFaultCode.INVALID_BYTECODE
    assert result.fault.validation_errors


def _compiled(source: SourceFile) -> BytecodeModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    return compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))


def _source_map_for(compiled: BytecodeModule, instruction_count: int) -> BytecodeSourceMap:
    function = compiled.functions[0]
    origin = compiled.source_map.entries[0]
    return BytecodeSourceMap(
        tuple(
            InstructionSourceMapEntry(
                function.function_id,
                InstructionIndex(index),
                origin.expression_id,
                origin.span,
            )
            for index in range(instruction_count)
        )
    )
