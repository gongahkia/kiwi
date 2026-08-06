from __future__ import annotations

from kiwi.dsl.bytecode import BytecodeHeader, BytecodeModule
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import BooleanValue
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.performance import benchmark_report, measure_operations, render_performance_report
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.state import MissionState


def test_measure_operations_uses_injected_clock_and_normalizes_elapsed_time() -> None:
    clock_values = iter((10, 35))
    calls: list[None] = []

    measurement = measure_operations(
        "compiler", 3, lambda: calls.append(None), now=lambda: next(clock_values)
    )

    assert calls == [None, None, None]
    assert measurement.elapsed_nanoseconds == 25
    assert measurement.nanoseconds_per_operation_text() == "8.333"


def test_benchmark_report_measures_each_focused_path_without_thresholds() -> None:
    source = SourceFile(
        SourceFileId("benchmark.dtr"),
        "policy choose(flag: Bool) -> Int = if flag then 1 else 2\n",
    )
    module = _compile(source)
    clock_values = iter((0, 10, 20, 40, 50, 80, 90, 130, 140, 190))

    report = benchmark_report(
        source,
        module,
        module.function_table.entries[0].function_id,
        (BooleanValue(True),),
        MissionState(),
        FixedTickClock(TickRate.HZ_30),
        iterations=1,
        ticks=1,
        now=lambda: next(clock_values),
    )

    assert tuple(measurement.name for measurement in report.measurements) == (
        "compiler",
        "vm",
        "tick",
        "trace",
        "replay_package",
    )
    assert tuple(measurement.operations for measurement in report.measurements) == (1, 1, 1, 1, 1)
    assert render_performance_report(report) == (
        "benchmark: informational; not a CI gate\n"
        "compiler: operations=1 elapsed_ns=10 ns_per_operation=10.000\n"
        "vm: operations=1 elapsed_ns=20 ns_per_operation=20.000\n"
        "tick: operations=1 elapsed_ns=30 ns_per_operation=30.000\n"
        "trace: operations=1 elapsed_ns=40 ns_per_operation=40.000\n"
        "replay_package: operations=1 elapsed_ns=50 ns_per_operation=50.000"
    )


def _compile(source: SourceFile) -> BytecodeModule:
    parsed = parse(lex(source))
    assert parsed.diagnostics == ()
    checked = check(resolve(parsed.module))
    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
