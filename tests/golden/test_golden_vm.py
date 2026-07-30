from __future__ import annotations

from pathlib import Path

from kiwi.dsl.bytecode import BytecodeHeader, BytecodeModule
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import BooleanValue, IntegerValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import VMBudgets, VMRunResult, run_vm

GOLDEN_ROOT = Path(__file__).parent


def test_vm_golden_fixture() -> None:
    source_path = GOLDEN_ROOT / "vm" / "basic.dtr"
    source = SourceFile(SourceFileId(source_path.name), source_path.read_text(encoding="utf-8"))
    module = _compiled(source)
    results = (
        ("choose(true)", run_vm(module, FunctionId(1), (BooleanValue(True),))),
        ("choose(false)", run_vm(module, FunctionId(1), (BooleanValue(False),))),
        (
            "instruction_budget(2)",
            run_vm(module, FunctionId(1), (BooleanValue(True),), VMBudgets(instruction_limit=2)),
        ),
    )

    actual = "\n".join(_format_result(label, result) for label, result in results) + "\n"

    assert actual == source_path.with_suffix(".vm").read_text(encoding="utf-8")


def _format_result(label: str, result: VMRunResult) -> str:
    if result.fault is None:
        assert isinstance(result.value, IntegerValue)
        return f"{label}: value=Integer({result.value.value})"
    assert result.fault.source_map_entry is not None
    assert result.fault.function_id is not None
    assert result.fault.instruction_index is not None
    source = result.fault.source_map_entry
    return (
        f"{label}: fault={result.fault.code} function={result.fault.function_id.value} "
        f"instruction={result.fault.instruction_index} expression={source.expression_id.value} "
        f"span={source.span.file_id.value!r}@{source.span.start.value}..{source.span.end.value}"
    )


def _compiled(source: SourceFile) -> BytecodeModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.module is not None
    return compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
