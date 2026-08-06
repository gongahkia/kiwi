"""Informational headless measurements outside authoritative packages."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from time import perf_counter_ns

from kiwi.dsl.bytecode import BytecodeHeader, BytecodeModule
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import RuntimeValue
from kiwi.dsl.source import SourceFile
from kiwi.dsl.vm import run_vm
from kiwi.replay.format import ReplayDecodeFailure, ReplayPacket, decode_replay, encode_replay
from kiwi.replay.recording import record_headless_run
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.hashing import StateHash, hash_canonical_state
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.state import MissionState
from kiwi.trace.capture import capture_run_trace


@dataclass(frozen=True, slots=True)
class PerformanceMeasurement:
    """Elapsed non-authoritative time for a positive number of operations."""

    name: str
    operations: int
    elapsed_nanoseconds: int

    def __post_init__(self) -> None:
        if not isinstance(self.name, str) or not self.name:
            raise ValueError("performance measurement name must be text")
        if not isinstance(self.operations, int) or isinstance(self.operations, bool):
            raise ValueError("performance measurement operations must be an integer")
        if self.operations <= 0:
            raise ValueError("performance measurement operations must be positive")
        if not isinstance(self.elapsed_nanoseconds, int) or isinstance(
            self.elapsed_nanoseconds, bool
        ):
            raise ValueError("performance measurement elapsed time must be an integer")
        if self.elapsed_nanoseconds < 0:
            raise ValueError("performance measurement elapsed time must be non-negative")

    def nanoseconds_per_operation_text(self) -> str:
        """Render a fixed three-decimal ns/op ratio without floating-point formatting."""
        whole, remainder = divmod(self.elapsed_nanoseconds, self.operations)
        fractional = remainder * 1_000 // self.operations
        return f"{whole}.{fractional:03d}"


@dataclass(frozen=True, slots=True)
class PerformanceReport:
    """The five focused Milestone 14 headless performance measurements."""

    compiler: PerformanceMeasurement
    vm: PerformanceMeasurement
    tick: PerformanceMeasurement
    trace: PerformanceMeasurement
    replay_package: PerformanceMeasurement

    def __post_init__(self) -> None:
        expected_names = ("compiler", "vm", "tick", "trace", "replay_package")
        actual_names = tuple(measurement.name for measurement in self.measurements)
        if actual_names != expected_names:
            raise ValueError("performance report measurements must use the fixed benchmark order")

    @property
    def measurements(self) -> tuple[PerformanceMeasurement, ...]:
        """Return measurements in the stable command-line output order."""
        return (self.compiler, self.vm, self.tick, self.trace, self.replay_package)


def measure_operations(
    name: str,
    operations: int,
    operation: Callable[[], object],
    *,
    now: Callable[[], int] = perf_counter_ns,
) -> PerformanceMeasurement:
    """Time a bounded operation count with an injectable non-authoritative clock."""
    if not isinstance(name, str) or not name:
        raise ValueError("performance operation name must be text")
    if not isinstance(operations, int) or isinstance(operations, bool) or operations <= 0:
        raise ValueError("performance operation count must be a positive integer")
    start = now()
    for _ in range(operations):
        operation()
    elapsed_nanoseconds = now() - start
    return PerformanceMeasurement(name, operations, elapsed_nanoseconds)


def benchmark_report(
    source: SourceFile,
    module: BytecodeModule,
    entry_function_id: FunctionId,
    arguments: tuple[RuntimeValue, ...],
    initial_state: MissionState,
    clock: FixedTickClock,
    *,
    iterations: int,
    ticks: int,
    now: Callable[[], int] = perf_counter_ns,
) -> PerformanceReport:
    """Measure compiler, VM, ticks, trace capture, and replay packet work headlessly."""
    if not isinstance(source, SourceFile):
        raise TypeError("performance benchmark source must be a source file")
    if not isinstance(module, BytecodeModule):
        raise TypeError("performance benchmark module must be bytecode")
    if not isinstance(entry_function_id, FunctionId):
        raise TypeError("performance benchmark entry must be a function ID")
    if not isinstance(arguments, tuple):
        raise TypeError("performance benchmark arguments must be an immutable tuple")
    if not isinstance(initial_state, MissionState):
        raise TypeError("performance benchmark initial state must be mission state")
    if not isinstance(clock, FixedTickClock):
        raise TypeError("performance benchmark clock must be fixed")
    if not isinstance(iterations, int) or isinstance(iterations, bool) or iterations <= 0:
        raise ValueError("performance benchmark iterations must be a positive integer")
    if not isinstance(ticks, int) or isinstance(ticks, bool) or ticks <= 0:
        raise ValueError("performance benchmark ticks must be a positive integer")

    run = run_headless(initial_state, clock, ticks)
    state_hash = hash_canonical_state(run.state)
    recorded = record_headless_run(
        initial_state,
        clock,
        ticks,
        application_build="benchmark",
        simulation_version="sim_v1",
        mission_hash=bytes(32),
    )

    compiler = measure_operations("compiler", iterations, lambda: _compile_source(source), now=now)
    vm = measure_operations(
        "vm", iterations, lambda: _run_entry(module, entry_function_id, arguments), now=now
    )
    tick = measure_operations(
        "tick",
        iterations * ticks,
        lambda: _run_ticks(initial_state, clock, ticks),
        now=now,
    )
    trace = measure_operations(
        "trace", iterations, lambda: _capture_trace(run, state_hash), now=now
    )
    replay_package = measure_operations(
        "replay_package", iterations, lambda: _round_trip_replay(recorded.replay), now=now
    )
    return PerformanceReport(compiler, vm, tick, trace, replay_package)


def render_performance_report(report: PerformanceReport) -> str:
    """Render an informational, stable text report without pass/fail thresholds."""
    if not isinstance(report, PerformanceReport):
        raise TypeError("performance report must be a PerformanceReport")
    lines = ["benchmark: informational; not a CI gate"]
    for measurement in report.measurements:
        lines.append(
            f"{measurement.name}: operations={measurement.operations} "
            f"elapsed_ns={measurement.elapsed_nanoseconds} "
            f"ns_per_operation={measurement.nanoseconds_per_operation_text()}"
        )
    return "\n".join(lines)


def _compile_source(source: SourceFile) -> BytecodeModule:
    parsed = parse(lex(source))
    if parsed.diagnostics:
        raise ValueError("performance benchmark source must parse without diagnostics")
    checked = check(resolve(parsed.module))
    if checked.diagnostics or checked.module is None:
        raise ValueError("performance benchmark source must check without diagnostics")
    return compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))


def _run_entry(
    module: BytecodeModule,
    entry_function_id: FunctionId,
    arguments: tuple[RuntimeValue, ...],
) -> None:
    result = run_vm(module, entry_function_id, arguments)
    if result.fault is not None:
        raise ValueError(f"performance benchmark VM fault: {result.fault.code}")


def _run_ticks(initial_state: MissionState, clock: FixedTickClock, ticks: int) -> None:
    run_headless(initial_state, clock, ticks)


def _capture_trace(run: HeadlessRun, state_hash: StateHash) -> None:
    capture_run_trace(run, state_hash)


def _round_trip_replay(replay: ReplayPacket) -> None:
    decoded = decode_replay(encode_replay(replay))
    if isinstance(decoded, ReplayDecodeFailure):
        raise ValueError(f"performance benchmark replay decode failed: {decoded.code}")
