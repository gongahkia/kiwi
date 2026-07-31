from __future__ import annotations

from kiwi.dsl.bytecode import BytecodeHeader, PushIntrinsic
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import (
    IntegerValue,
    ListValue,
    OptionSomeValue,
    RecordValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import VMBudgets, VMFaultCode, run_vm


def test_list_intrinsics_compile_encode_and_preserve_source_order_ties() -> None:
    source = SourceFile(
        SourceFileId("list-intrinsics.dtr"),
        "type Candidate = { id: Int, key: Int }\n"
        "policy mapped() -> List<Int> = List.map("
        "[Candidate { id = 2, key = 1 }, Candidate { id = 1, key = 1 }], fn item -> item.id)\n"
        "policy filtered() -> List<Int> = List.filter([2, 1], fn item -> false)\n"
        "policy folded() -> Candidate = List.fold("
        "[Candidate { id = 2, key = 1 }, Candidate { id = 1, key = 1 }], "
        "Candidate { id = 0, key = 0 }, fn (accumulator, item) -> item)\n"
        "policy found() -> Option<Int> = List.find([2, 1], fn item -> true)\n"
        "policy minimum() -> Option<Candidate> = List.min_by("
        "[Candidate { id = 2, key = 1 }, Candidate { id = 1, key = 1 }], "
        "fn item -> item.key)\n"
        "policy ordered() -> List<Candidate> = List.sort_by("
        "[Candidate { id = 2, key = 1 }, Candidate { id = 3, key = 0 }, "
        "Candidate { id = 1, key = 1 }], fn item -> item.key)\n"
        "fn captured(seed: Int) -> List<Int> = List.map([1, 2], fn item -> seed)\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    assert any(
        isinstance(instruction, PushIntrinsic)
        for function in module.functions
        for instruction in function.instructions
    )
    assert decode_bytecode(encode_bytecode(module)) == module

    assert run_vm(module, FunctionId(0), ()).value == ListValue((IntegerValue(2), IntegerValue(1)))
    assert run_vm(module, FunctionId(1), ()).value == ListValue(())
    assert run_vm(module, FunctionId(2), ()).value == RecordValue(
        "Candidate", ("id", "key"), (IntegerValue(1), IntegerValue(1))
    )
    assert run_vm(module, FunctionId(3), ()).value == OptionSomeValue(IntegerValue(2))
    assert run_vm(module, FunctionId(4), ()).value == OptionSomeValue(
        RecordValue("Candidate", ("id", "key"), (IntegerValue(2), IntegerValue(1)))
    )
    assert run_vm(module, FunctionId(5), ()).value == ListValue(
        (
            RecordValue("Candidate", ("id", "key"), (IntegerValue(3), IntegerValue(0))),
            RecordValue("Candidate", ("id", "key"), (IntegerValue(2), IntegerValue(1))),
            RecordValue("Candidate", ("id", "key"), (IntegerValue(1), IntegerValue(1))),
        )
    )
    assert run_vm(module, FunctionId(6), (IntegerValue(9),)).value == ListValue(
        (IntegerValue(9), IntegerValue(9))
    )


def test_list_intrinsics_reject_invalid_static_uses() -> None:
    source = SourceFile(
        SourceFileId("list-intrinsics-invalid.dtr"),
        "type Pair = { value: Int }\n"
        "fn arity() -> List<Int> = List.map([1])\n"
        "fn list() -> List<Int> = List.map(1, fn item -> item)\n"
        "fn callback() -> List<Int> = List.map([1], fn (left, right) -> left)\n"
        "fn order() -> List<Int> = List.sort_by([1], fn item -> Pair { value = item })\n"
        "fn reference() -> Int = List.map\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E425_INTRINSIC_ARITY",
        "E426_INTRINSIC_LIST",
        "E422_LAMBDA_ARITY",
        "E428_INTRINSIC_ORDER_KEY",
        "E424_INTRINSIC_CALL",
    )


def test_list_intrinsics_charge_traversal_and_output_allocations() -> None:
    source = SourceFile(
        SourceFileId("list-intrinsics-budget.dtr"),
        "fn mapped() -> List<Int> = List.map([1, 2], fn item -> item)\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    allocation_fault = run_vm(module, FunctionId(0), (), VMBudgets(allocation_limit=7))
    instruction_fault = run_vm(module, FunctionId(0), (), VMBudgets(instruction_limit=11))
    completed = run_vm(
        module,
        FunctionId(0),
        (),
        VMBudgets(instruction_limit=20, allocation_limit=8),
    )

    assert allocation_fault.fault is not None
    assert allocation_fault.fault.code is VMFaultCode.ALLOCATION_BUDGET
    assert allocation_fault.fault.source_map_entry is not None
    assert instruction_fault.fault is not None
    assert instruction_fault.fault.code is VMFaultCode.INSTRUCTION_BUDGET
    assert instruction_fault.fault.source_map_entry is not None
    assert completed.value == ListValue((IntegerValue(1), IntegerValue(2)))
