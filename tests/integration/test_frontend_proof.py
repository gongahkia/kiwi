from __future__ import annotations

from pathlib import Path

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import (
    MemoryField,
    MemorySchema,
    ValidatedPolicyResult,
    validate_policy_result,
)
from kiwi.dsl.runtime_values import IntegerValue, OptionSomeValue, QuantityValue, RecordValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import NamedType
from kiwi.dsl.vm import run_vm

EXAMPLE_POLICY = Path(__file__).resolve().parents[2] / "examples" / "policies" / "basic.dtr"
M4_EXAMPLE_POLICY = (
    Path(__file__).resolve().parents[2] / "examples" / "policies" / "m4-language.dtr"
)


def test_first_proof_policy_parses() -> None:
    source = SourceFile(
        SourceFileId("examples/policies/basic.dtr"),
        EXAMPLE_POLICY.read_text(encoding="utf-8"),
    )

    result = parse(lex(source))

    assert result.diagnostics == ()
    assert len(result.module.declarations) == 1


def test_milestone_four_language_example_compiles_executes_and_validates_decision() -> None:
    source = SourceFile(
        SourceFileId("examples/policies/m4-language.dtr"),
        M4_EXAMPLE_POLICY.read_text(encoding="utf-8"),
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    lowered = lower(checked.module)
    assert lowered.module.definitions[0].name == "choose"
    module = compile_core(lowered.module, BytecodeHeader(source.file_id))
    target = _position(4, 2)
    memory = RecordValue("Memory", ("origin",), (_position(1, 2),))

    result = run_vm(module, FunctionId(0), (memory, OptionSomeValue(target)))

    assert result.fault is None
    assert result.value is not None
    assert validate_policy_result(
        result.value,
        MemorySchema("Memory", (MemoryField("origin", NamedType("Position")),)),
    ) == ValidatedPolicyResult(
        RecordValue("Memory", ("origin",), (_position(5, 2),)),
        (IntegerValue(1), IntegerValue(2)),
    )


def _position(x: int, y: int) -> RecordValue:
    return RecordValue(
        "Position",
        ("x", "y"),
        (
            QuantityValue(Quantity(QuantityDimension.DISTANCE, ExactRational(x, 1))),
            QuantityValue(Quantity(QuantityDimension.DISTANCE, ExactRational(y, 1))),
        ),
    )
