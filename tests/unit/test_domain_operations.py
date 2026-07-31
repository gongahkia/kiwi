from __future__ import annotations

import pytest

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import BinaryOperation, BytecodeHeader, BytecodeModule
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import BooleanValue, QuantityValue, RecordValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.vm import VMBudgets, VMFaultCode, run_vm


def test_domain_operations_compile_encode_and_execute_exactly() -> None:
    source = SourceFile(
        SourceFileId("domain-operations.dtr"),
        "fn elapsed() -> Duration = 1s + 250ms\n"
        "fn range() -> Distance = 8m - 3m\n"
        "fn likely() -> Bool = 70% >= 1%\n"
        "fn moved() -> Position = "
        "Position { x = 1m, y = 2m } + Vector { dx = 3m, dy = 4m }\n"
        "fn displacement() -> Vector = "
        "Position { x = 4m, y = 7m } - Position { x = 1m, y = 2m }\n"
        "fn summed() -> Vector = "
        "Vector { dx = 1m, dy = 2m } + Vector { dx = 3m, dy = 4m }\n"
        "fn adjusted() -> Vector = "
        "Vector { dx = 3m, dy = 4m } - Vector { dx = 1m, dy = 2m }\n",
    )
    parsed = parse(lex(source))
    checked = check(resolve(parsed.module))

    assert parsed.diagnostics == ()
    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    assert any(
        isinstance(instruction, BinaryOperation)
        for function in module.functions
        for instruction in function.instructions
    )
    assert decode_bytecode(encode_bytecode(module)) == module

    assert run_vm(module, FunctionId(0), ()).value == _quantity(QuantityDimension.DURATION, 5, 4)
    assert run_vm(module, FunctionId(1), ()).value == _quantity(QuantityDimension.DISTANCE, 5)
    assert run_vm(module, FunctionId(2), ()).value == BooleanValue(True)
    assert run_vm(module, FunctionId(3), ()).value == RecordValue(
        "Position",
        ("x", "y"),
        (_quantity(QuantityDimension.DISTANCE, 4), _quantity(QuantityDimension.DISTANCE, 6)),
    )
    assert run_vm(module, FunctionId(4), ()).value == RecordValue(
        "Vector",
        ("dx", "dy"),
        (_quantity(QuantityDimension.DISTANCE, 3), _quantity(QuantityDimension.DISTANCE, 5)),
    )
    assert run_vm(module, FunctionId(5), ()).value == RecordValue(
        "Vector",
        ("dx", "dy"),
        (_quantity(QuantityDimension.DISTANCE, 4), _quantity(QuantityDimension.DISTANCE, 6)),
    )
    assert run_vm(module, FunctionId(6), ()).value == RecordValue(
        "Vector",
        ("dx", "dy"),
        (_quantity(QuantityDimension.DISTANCE, 2), _quantity(QuantityDimension.DISTANCE, 2)),
    )


@pytest.mark.parametrize(
    ("source_text", "operator"),
    (
        ("fn invalid() -> Distance = 1m + 1s", "+"),
        ("fn invalid() -> Probability = 70% + 10%", "+"),
        (
            "fn invalid() -> Position = Vector { dx = 1m, dy = 2m } + Position { x = 3m, y = 4m }",
            "+",
        ),
        ("fn invalid() -> Bool = 90deg > 45deg", ">"),
    ),
)
def test_domain_operations_reject_invalid_dimensions(
    source_text: str,
    operator: str,
) -> None:
    source = SourceFile(SourceFileId("invalid-domain-operations.dtr"), source_text)
    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert len(result.diagnostics) == 1
    diagnostic = result.diagnostics[0]
    assert diagnostic.code == "E429_INVALID_DOMAIN_OPERATION"
    operator_start = source_text.rindex(operator)
    assert diagnostic.primary_span == source.span(
        ByteOffset(operator_start), ByteOffset(operator_start + len(operator))
    )


def test_domain_operations_charge_bounded_allocation_costs() -> None:
    source = SourceFile(
        SourceFileId("domain-operation-budgets.dtr"),
        "fn quantity() -> Distance = 1m + 2m\n"
        "fn position() -> Position = "
        "Position { x = 1m, y = 2m } + Vector { dx = 3m, dy = 4m }\n",
    )
    module = _compiled(source)

    quantity_fault = run_vm(module, FunctionId(0), (), VMBudgets(allocation_limit=0))
    quantity = run_vm(module, FunctionId(0), (), VMBudgets(allocation_limit=1))
    position_fault = run_vm(module, FunctionId(1), (), VMBudgets(allocation_limit=4))
    position = run_vm(module, FunctionId(1), (), VMBudgets(allocation_limit=5))

    assert quantity_fault.fault is not None
    assert quantity_fault.fault.code is VMFaultCode.ALLOCATION_BUDGET
    assert quantity.value == _quantity(QuantityDimension.DISTANCE, 3)
    assert position_fault.fault is not None
    assert position_fault.fault.code is VMFaultCode.ALLOCATION_BUDGET
    assert position.value == RecordValue(
        "Position",
        ("x", "y"),
        (_quantity(QuantityDimension.DISTANCE, 4), _quantity(QuantityDimension.DISTANCE, 6)),
    )


def test_legacy_bytecode_rejects_domain_operations() -> None:
    source = SourceFile(
        SourceFileId("legacy-domain-operation.dtr"),
        "fn sum() -> Distance = 1m + 2m",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    with pytest.raises(ValueError, match="version 1"):
        compile_core(lower(checked.module).module, BytecodeHeader(source.file_id, 1, 1, 1))


def _compiled(source: SourceFile) -> BytecodeModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))


def _quantity(
    dimension: QuantityDimension,
    numerator: int,
    denominator: int = 1,
) -> QuantityValue:
    return QuantityValue(Quantity(dimension, ExactRational(numerator, denominator)))
