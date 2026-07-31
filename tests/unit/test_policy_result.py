from __future__ import annotations

import pytest

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
    PolicyResultValidationCode,
    PolicyResultValidationFailure,
    ValidatedPolicyResult,
    validate_memory,
    validate_policy_result,
)
from kiwi.dsl.runtime_values import (
    IntegerValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
    RecordValue,
    StringValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType, FunctionType, OptionType
from kiwi.dsl.vm import run_vm

MEMORY_SCHEMA = MemorySchema(
    "Memory",
    (
        MemoryField("label", BuiltinType.STRING),
        MemoryField("target", OptionType(BuiltinType.INT)),
    ),
)


def test_policy_result_validator_accepts_compiled_memory_and_decision_records() -> None:
    source = SourceFile(
        SourceFileId("policy-result.dtr"),
        "type Memory = { label: String, target: Option<Int> }\n"
        "type Decision = { intentions: List<Int>, memory: Memory }\n"
        "policy choose(memory: Memory) -> Decision = "
        "Decision { intentions = [], memory = memory }\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    memory = RecordValue(
        "Memory",
        ("label", "target"),
        (StringValue("cautious"), OptionSomeValue(IntegerValue(7))),
    )
    vm_result = run_vm(module, FunctionId(0), (memory,))

    assert vm_result.value is not None
    validated = validate_policy_result(vm_result.value, MEMORY_SCHEMA)
    assert validated == ValidatedPolicyResult(memory, ())


def test_policy_result_validator_reports_memory_and_decision_shapes() -> None:
    valid_memory = RecordValue(
        "Memory",
        ("label", "target"),
        (StringValue("cautious"), OptionNoneValue()),
    )
    malformed_memory = RecordValue(
        "Memory",
        ("label", "target"),
        (IntegerValue(1), OptionNoneValue()),
    )

    memory_failure = validate_memory(malformed_memory, MEMORY_SCHEMA)
    assert memory_failure == PolicyResultValidationFailure(
        PolicyResultValidationCode.MEMORY_SHAPE,
        "memory field 'label' must have type String",
        ("label",),
    )

    malformed_decision = RecordValue(
        "Decision",
        ("intentions", "memory"),
        (IntegerValue(1), valid_memory),
    )
    decision_failure = validate_policy_result(malformed_decision, MEMORY_SCHEMA)
    assert decision_failure == PolicyResultValidationFailure(
        PolicyResultValidationCode.INTENTION_SHAPE,
        "Decision.intentions must be a List value",
        ("intentions",),
    )

    memory_in_decision_failure = validate_policy_result(
        RecordValue(
            "Decision",
            ("intentions", "memory"),
            (ListValue(()), malformed_memory),
        ),
        MEMORY_SCHEMA,
    )
    assert memory_in_decision_failure == PolicyResultValidationFailure(
        PolicyResultValidationCode.MEMORY_SHAPE,
        "memory field 'label' must have type String",
        ("memory", "label"),
    )


def test_memory_schemas_reject_function_values() -> None:
    with pytest.raises(ValueError, match="data types"):
        MemoryField("callback", FunctionType((), BuiltinType.INT))
    with pytest.raises(ValueError, match="immutable tuple"):
        MemorySchema("Memory", [])  # type: ignore[arg-type]
