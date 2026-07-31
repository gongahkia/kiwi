from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import BuildClosure, BytecodeHeader
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import (
    MAX_RUNTIME_CLOSURE_CAPTURES,
    ClosureValue,
    IntegerValue,
    ListValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import VMBudgets, VMFaultCode, run_vm


def test_lambdas_capture_values_compile_encode_and_execute() -> None:
    source = SourceFile(
        SourceFileId("lambdas.dtr"),
        "fn capture(seed: Int) -> Int -> Int = fn value -> seed\n"
        "fn call() -> Int = capture(7)(0)\n"
        "fn apply(f: Int -> Int, value: Int) -> Int = f(value)\n"
        "fn direct() -> Int = apply(fn item -> item, 3)\n"
        "fn nested(seed: Int) -> Int -> Int -> Int = fn first -> fn second -> seed\n"
        "fn call_nested() -> Int = nested(9)(1)(2)\n"
        "fn pack(first: Int, second: Int) -> Int -> List<Int> = fn item -> [second, first]\n"
        "fn packed() -> List<Int> = pack(1, 2)(0)\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    lowered = lower(checked.module)
    module = compile_core(lowered.module, BytecodeHeader(source.file_id))
    assert any(
        isinstance(instruction, BuildClosure)
        for function in module.functions
        for instruction in function.instructions
    )
    assert decode_bytecode(encode_bytecode(module)) == module

    captured = run_vm(module, FunctionId(0), (IntegerValue(7),))
    assert isinstance(captured.value, ClosureValue)
    assert captured.value.captures == (IntegerValue(7),)
    assert run_vm(module, FunctionId(1), ()).value == IntegerValue(7)
    assert run_vm(module, FunctionId(3), ()).value == IntegerValue(3)
    assert run_vm(module, FunctionId(5), ()).value == IntegerValue(9)
    packed_closure = run_vm(module, FunctionId(6), (IntegerValue(1), IntegerValue(2)))
    assert isinstance(packed_closure.value, ClosureValue)
    assert packed_closure.value.captures == (IntegerValue(2), IntegerValue(1))
    assert run_vm(module, FunctionId(7), ()).value == ListValue((IntegerValue(2), IntegerValue(1)))
    with pytest.raises(ValueError, match="version 1"):
        compile_core(lowered.module, BytecodeHeader(source.file_id, 1, 1, 1))


def test_lambdas_require_context_correct_arity_and_bounded_captures() -> None:
    captures = ", ".join(f"value{index}" for index in range(MAX_RUNTIME_CLOSURE_CAPTURES + 1))
    bindings = " ".join(
        f"let value{index} = {index} in" for index in range(MAX_RUNTIME_CLOSURE_CAPTURES + 1)
    )
    source = SourceFile(
        SourceFileId("lambdas-invalid.dtr"),
        "fn missing() -> Int = fn value -> value\n"
        "fn arity() -> Int -> Int = fn (left, right) -> left\n"
        f"fn captures() -> Int -> List<Int> = {bindings} fn item -> [{captures}]\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E421_AMBIGUOUS_LAMBDA",
        "E422_LAMBDA_ARITY",
        "E423_CLOSURE_CAPTURE_LIMIT",
    )


def test_lambdas_charge_captures_plus_container_before_construction() -> None:
    source = SourceFile(
        SourceFileId("lambda-budget.dtr"),
        "fn capture(seed: Int) -> Int -> Int = fn value -> seed\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    exhausted = run_vm(module, FunctionId(0), (IntegerValue(4),), VMBudgets(allocation_limit=1))
    completed = run_vm(module, FunctionId(0), (IntegerValue(4),), VMBudgets(allocation_limit=2))

    assert exhausted.fault is not None
    assert exhausted.fault.code is VMFaultCode.ALLOCATION_BUDGET
    assert isinstance(completed.value, ClosureValue)


def test_lambdas_support_zero_and_multiple_contextual_parameters() -> None:
    source = SourceFile(
        SourceFileId("lambda-arities.dtr"),
        "fn first() -> (Int, Bool) -> Int = fn (number, flag) -> number\n"
        "fn zero() -> () -> Int = fn () -> 1\n"
        "fn first_value() -> Int = first()(4, true)\n"
        "fn zero_value() -> Int = zero()()\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))

    assert run_vm(module, FunctionId(2), ()).value == IntegerValue(4)
    assert run_vm(module, FunctionId(3), ()).value == IntegerValue(1)
