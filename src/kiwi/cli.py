"""Headless command-line entry points."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from hashlib import blake2b
from pathlib import Path

from kiwi.app.persistence import backup_path, write_recoverable_file
from kiwi.content.fixtures import (
    FixtureLoadFailure,
    load_kernel_fixture_bytes,
    load_kernel_fixture_file,
)
from kiwi.content.missions import MissionLoadFailure, load_mission_file
from kiwi.content.projects import (
    POLICY_PROJECT_FILENAME,
    PolicyProjectDiagnostic,
    PolicyProjectValidationFailure,
    validate_policy_project_file,
)
from kiwi.domain.ids import IntentionId, TraceNodeId
from kiwi.dsl.bytecode import BytecodeHeader, BytecodeModule
from kiwi.dsl.bytecode_codec import encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.core_debug import format_lower_result
from kiwi.dsl.debug import format_surface_module
from kiwi.dsl.diagnostics import Diagnostic
from kiwi.dsl.disassemble import disassemble
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import MAX_INTEGER_DIGITS, lex
from kiwi.dsl.lower import LowerResult, lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import (
    BooleanValue,
    ClosureValue,
    IntegerValue,
    IntrinsicValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    RuntimeValue,
    StringValue,
    UnitValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId, SourceLoadFailure, load_utf8_file
from kiwi.dsl.vm import run_vm
from kiwi.performance import benchmark_report, render_performance_report
from kiwi.replay.compatibility import check_run_compatibility
from kiwi.replay.format import (
    ReplayDecodeFailure,
    ReplayPacket,
    decode_replay,
    encode_replay,
    hash_replay,
)
from kiwi.replay.recording import record_headless_run
from kiwi.replay.verification import ReplayVerificationFailure, verify_replay
from kiwi.sim.bootstrap import build_initial_state
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.intentions import IntentionOrigin
from kiwi.sim.randomness import MissionSeed
from kiwi.trace.format import TraceDecodeFailure, decode_trace
from kiwi.trace.model import (
    CausalTrace,
    ConsequenceTrace,
    IntentionResolutionTrace,
    IntentionTrace,
    TraceRecord,
    WorldEventTrace,
)
from kiwi.trace.queries import (
    ConsequenceChainExplanation,
    ConsequenceQueryUnavailable,
    IntentionFailureExplanation,
    IntentionRejectionExplanation,
    IntentionSelectionExplanation,
    TraceQueryUnavailable,
    consequence_chain,
    why_failed,
    why_not_selected,
    why_selected,
)

_MINIMUM_PYTHON = (3, 12)


def doctor() -> int:
    """Check the minimum headless runtime contract."""
    if sys.version_info[:2] < _MINIMUM_PYTHON:
        print("kiwi doctor: Python 3.12 or later is required", file=sys.stderr)
        return 1
    if "pygame" in sys.modules:
        print("kiwi doctor: pygame was imported", file=sys.stderr)
        return 1
    print("kiwi doctor: ok")
    print(f"python: {sys.version_info.major}.{sys.version_info.minor}")
    print("pygame imported: no")
    return 0


def parse_source(path: Path) -> int:
    """Parse one source file and render either diagnostics or stable surface syntax."""
    source = _load_source(path)
    if source is None:
        return 1
    result = parse(lex(source))
    if result.diagnostics:
        for diagnostic in result.diagnostics:
            print(_format_diagnostic(source, diagnostic), file=sys.stderr)
        return 1
    print(format_surface_module(result.module))
    return 0


def check_source(path: Path) -> int:
    """Type-check and lower one source file without importing pygame."""
    source = _load_source(path)
    if source is None:
        return 1
    lowered = _check_and_lower(source)
    if lowered is None:
        return 1
    print(format_lower_result(lowered))
    return 0


def compile_source(path: Path, output: Path | None = None) -> int:
    """Compile source to canonical bytecode, optionally writing it to one path."""
    module = _compile_source(path)
    if module is None:
        return 1
    encoded = encode_bytecode(module)
    if output is None:
        print(f"{path}: compiled {len(encoded)} bytes")
        return 0
    try:
        output.write_bytes(encoded)
    except OSError:
        print(f"{output}: could not write bytecode", file=sys.stderr)
        return 1
    print(f"{output}: wrote {len(encoded)} bytes")
    return 0


def disassemble_source(path: Path) -> int:
    """Compile source and render its bytecode in stable headless text."""
    module = _compile_source(path)
    if module is None:
        return 1
    print(disassemble(module))
    return 0


def run_policy_source(path: Path, entry_name: str, argument_texts: Sequence[str]) -> int:
    """Compile and execute one named entry with explicit closed runtime values."""
    module = _compile_source(path)
    if module is None:
        return 1
    entry_function_id = _function_id_for_name(module, entry_name)
    if entry_function_id is None:
        print(f"{path}: R013_ENTRY: no function named {entry_name!r}", file=sys.stderr)
        return 1
    arguments: list[RuntimeValue] = []
    for text in argument_texts:
        value = _parse_runtime_argument(text)
        if value is None:
            print(
                f"run-policy: unsupported argument {text!r}; use an integer, true, false, or unit",
                file=sys.stderr,
            )
            return 1
        arguments.append(value)
    result = run_vm(module, entry_function_id, tuple(arguments))
    if result.fault is not None:
        print(f"fault: {result.fault.code}: {result.fault.message}", file=sys.stderr)
        return 1
    if result.value is None:
        raise AssertionError("successful VM result has no value")
    print(f"value: {_format_runtime_value(result.value)}")
    return 0


def benchmark(
    source_path: Path,
    fixture_path: Path,
    entry_name: str,
    argument_texts: Sequence[str],
    iterations: int,
    ticks: int,
) -> int:
    """Measure the focused headless compiler, VM, simulation, trace, and replay paths."""
    if not isinstance(iterations, int) or isinstance(iterations, bool) or iterations <= 0:
        print("benchmark: iterations must be a positive integer", file=sys.stderr)
        return 1
    if not isinstance(ticks, int) or isinstance(ticks, bool) or ticks <= 0:
        print("benchmark: ticks must be a positive integer", file=sys.stderr)
        return 1
    source = _load_source(source_path)
    if source is None:
        return 1
    lowered = _check_and_lower(source)
    if lowered is None:
        return 1
    module = compile_core(lowered.module, BytecodeHeader(source.file_id))
    entry_function_id = _function_id_for_name(module, entry_name)
    if entry_function_id is None:
        print(f"{source_path}: R013_ENTRY: no function named {entry_name!r}", file=sys.stderr)
        return 1
    arguments: list[RuntimeValue] = []
    for text in argument_texts:
        value = _parse_runtime_argument(text)
        if value is None:
            print(
                f"benchmark: unsupported argument {text!r}; use an integer, true, false, or unit",
                file=sys.stderr,
            )
            return 1
        arguments.append(value)
    try:
        fixture_bytes = fixture_path.read_bytes()
    except OSError:
        print(f"{fixture_path}: could not read fixture", file=sys.stderr)
        return 1
    fixture = load_kernel_fixture_bytes(fixture_bytes, str(fixture_path))
    if isinstance(fixture, FixtureLoadFailure):
        _print_fixture_failure(fixture)
        return 1
    state = build_initial_state(
        MissionSeed(fixture.seed),
        tuple(entity.position for entity in fixture.entities),
        fixture.scheduled_trigger_ticks,
    )
    try:
        report = benchmark_report(
            source,
            module,
            entry_function_id,
            tuple(arguments),
            state,
            FixedTickClock(TickRate(fixture.tick_rate)),
            iterations=iterations,
            ticks=ticks,
        )
    except ValueError as error:
        print(f"benchmark: {error}", file=sys.stderr)
        return 1
    print(render_performance_report(report))
    return 0


def validate_paths(paths: Sequence[Path]) -> int:
    """Validate supported content and closed-DSL projects without importing pygame."""
    if not isinstance(paths, Sequence) or not paths:
        raise ValueError("validation requires at least one path")
    files = _validation_files(paths)
    if not files:
        print("validate: no supported content or policy files found", file=sys.stderr)
        return 1
    failed = False
    for path in files:
        if path.name == POLICY_PROJECT_FILENAME:
            project_result = validate_policy_project_file(path)
            if isinstance(project_result, PolicyProjectValidationFailure):
                _print_policy_project_failure(project_result)
                failed = True
            else:
                print(f"ok: {path}: policy project entries={len(project_result.entries)}")
            continue
        if path.name.endswith(".dmission.json"):
            mission_result = load_mission_file(path)
            if isinstance(mission_result, MissionLoadFailure):
                _print_mission_failure(mission_result)
                failed = True
            else:
                print(f"ok: {path}: mission id={mission_result.mission_id}")
            continue
        if path.name.endswith(".kfixture.json"):
            fixture_result = load_kernel_fixture_file(path)
            if isinstance(fixture_result, FixtureLoadFailure):
                _print_fixture_failure(fixture_result)
                failed = True
            else:
                print(f"ok: {path}: kernel fixture id={fixture_result.fixture_id}")
            continue
        if path.suffix == ".dtr":
            module = _compile_source(path)
            if module is None:
                failed = True
            else:
                print(f"ok: {path}: policy source")
            continue
        print(f"{path}: V001_UNSUPPORTED_PATH: unsupported validation target", file=sys.stderr)
        failed = True
    return 1 if failed else 0


def trace_query(path: Path, query_name: str, target_id: int) -> int:
    """Load one trace packet and render one deterministic evidence-only query."""
    if not isinstance(path, Path):
        raise TypeError("trace query path must be a path")
    if not isinstance(query_name, str):
        raise TypeError("trace query name must be text")
    if not isinstance(target_id, int) or isinstance(target_id, bool) or target_id <= 0:
        print("trace-query: target ID must be a positive integer", file=sys.stderr)
        return 1
    trace = _load_trace(path)
    if trace is None:
        return 1
    if query_name == "why-selected":
        _print_selected_query(why_selected(trace, IntentionId(target_id)))
        return 0
    if query_name == "why-not-selected":
        _print_not_selected_query(why_not_selected(trace, IntentionId(target_id)))
        return 0
    if query_name == "why-failed":
        _print_failed_query(why_failed(trace, IntentionId(target_id)))
        return 0
    if query_name == "consequence-chain":
        _print_consequence_query(consequence_chain(trace, TraceNodeId(target_id)))
        return 0
    raise ValueError("trace query name is unsupported")


def replay_record(
    fixture_path: Path,
    ticks: int,
    output: Path,
    application_build: str,
    simulation_version: str,
) -> int:
    """Record one policy-free fixture run into an immutable replay packet."""
    if not isinstance(ticks, int) or isinstance(ticks, bool) or ticks < 0:
        print("replay-record: ticks must be a non-negative integer", file=sys.stderr)
        return 1
    try:
        fixture_bytes = fixture_path.read_bytes()
    except OSError:
        print(f"{fixture_path}: could not read fixture", file=sys.stderr)
        return 1
    fixture = load_kernel_fixture_bytes(fixture_bytes, str(fixture_path))
    if isinstance(fixture, FixtureLoadFailure):
        _print_fixture_failure(fixture)
        return 1
    try:
        recorded = record_headless_run(
            build_initial_state(
                MissionSeed(fixture.seed),
                tuple(entity.position for entity in fixture.entities),
                fixture.scheduled_trigger_ticks,
            ),
            FixedTickClock(TickRate(fixture.tick_rate)),
            ticks,
            application_build=application_build,
            simulation_version=simulation_version,
            mission_hash=blake2b(fixture_bytes, digest_size=32).digest(),
        )
        encoded = encode_replay(recorded.replay)
    except ValueError as error:
        print(f"replay-record: {error}", file=sys.stderr)
        return 1
    write_failure = write_recoverable_file(output, encoded)
    if write_failure is not None:
        print(f"{output}: {write_failure.code}: {write_failure.message}", file=sys.stderr)
        return 1
    print(
        f"{output}: wrote {len(encoded)} bytes "
        f"checkpoints={len(recorded.replay.checkpoints)} hash={hash_replay(recorded.replay).hex()}"
    )
    return 0


def replay_verify(path: Path) -> int:
    """Verify one policy-free recorded replay through its canonical checkpoints."""
    replay = _load_replay(path)
    if replay is None:
        return 1
    result = verify_replay(replay)
    if isinstance(result, ReplayVerificationFailure):
        print(f"{path}: {result.code}: {result.message}", file=sys.stderr)
        return 1
    print(f"verified: tick={result.state.tick} checkpoints={len(replay.checkpoints)}")
    return 0


def replay_inspect(path: Path) -> int:
    """Render deterministic immutable replay metadata without executing authority."""
    replay = _load_replay(path)
    if replay is None:
        return 1
    print("format: KWI-RUN v1")
    print(f"hash: {hash_replay(replay).hex()}")
    print(f"application_build: {replay.application_build}")
    print(f"simulation_version: {replay.simulation_version}")
    print(f"mission_hash: {replay.mission_hash.hex()}")
    print(f"seed: {replay.seed.value}")
    print(f"tick_rate: {int(replay.tick_rate)}")
    print(f"commands: {len(replay.commands)}")
    print(f"checkpoints: {len(replay.checkpoints)}")
    print(f"policy_versions: {len(replay.policy_versions)}")
    return 0


def replay_compare(expected_path: Path, actual_path: Path) -> int:
    """Report baseline compatibility and deployed-policy deltas for two replay packets."""
    expected = _load_replay(expected_path)
    actual = _load_replay(actual_path)
    if expected is None or actual is None:
        return 1
    compatibility = check_run_compatibility(expected, actual)
    print(f"compatible: {'yes' if compatibility.is_compatible else 'no'}")
    for failure in compatibility.failures:
        print(f"incompatible: {failure.code}: {failure.message}")
    for difference in compatibility.policy_differences:
        expected_digest = (
            difference.expected_version.digest.hex()
            if difference.expected_version is not None
            else "none"
        )
        actual_digest = (
            difference.actual_version.digest.hex()
            if difference.actual_version is not None
            else "none"
        )
        print(
            "policy: "
            f"entity={difference.entity_id.value} kind={difference.kind.value} "
            f"expected={expected_digest} actual={actual_digest}"
        )
    return 0 if compatibility.is_compatible else 1


def _load_source(path: Path) -> SourceFile | None:
    source_or_failure = load_utf8_file(path, file_id=SourceFileId(str(path)))
    if isinstance(source_or_failure, SourceLoadFailure):
        print(
            f"{source_or_failure.file_id.value}: {source_or_failure.code}: "
            f"{source_or_failure.message}",
            file=sys.stderr,
        )
        return None
    return source_or_failure


def _load_trace(path: Path) -> CausalTrace | None:
    try:
        data = path.read_bytes()
    except OSError:
        return _load_trace_backup(path, "TR000_READ_FAILED", "could not read trace")
    decoded = decode_trace(data)
    if isinstance(decoded, TraceDecodeFailure):
        return _load_trace_backup(path, decoded.code.value, decoded.message)
    return decoded


def _load_replay(path: Path) -> ReplayPacket | None:
    try:
        data = path.read_bytes()
    except OSError:
        return _load_replay_backup(path, "RP000_READ_FAILED", "could not read replay")
    decoded = decode_replay(data)
    if isinstance(decoded, ReplayDecodeFailure):
        return _load_replay_backup(path, decoded.code.value, decoded.message)
    return decoded


def _load_trace_backup(path: Path, primary_code: str, primary_message: str) -> CausalTrace | None:
    backup = backup_path(path)
    try:
        data = backup.read_bytes()
    except OSError:
        print(f"{path}: {primary_code}: {primary_message}", file=sys.stderr)
        return None
    decoded = decode_trace(data)
    if isinstance(decoded, TraceDecodeFailure):
        print(f"{path}: {primary_code}: {primary_message}", file=sys.stderr)
        return None
    print(f"{path}: recovered from {backup}", file=sys.stderr)
    return decoded


def _load_replay_backup(path: Path, primary_code: str, primary_message: str) -> ReplayPacket | None:
    backup = backup_path(path)
    try:
        data = backup.read_bytes()
    except OSError:
        print(f"{path}: {primary_code}: {primary_message}", file=sys.stderr)
        return None
    decoded = decode_replay(data)
    if isinstance(decoded, ReplayDecodeFailure):
        print(f"{path}: {primary_code}: {primary_message}", file=sys.stderr)
        return None
    print(f"{path}: recovered from {backup}", file=sys.stderr)
    return decoded


def _print_fixture_failure(failure: FixtureLoadFailure) -> None:
    for diagnostic in failure.diagnostics:
        print(
            f"{failure.source}:{diagnostic.path}: {diagnostic.code}: {diagnostic.message}",
            file=sys.stderr,
        )


def _print_mission_failure(failure: MissionLoadFailure) -> None:
    for diagnostic in failure.diagnostics:
        print(
            f"{failure.source}:{diagnostic.path}: {diagnostic.code}: {diagnostic.message}",
            file=sys.stderr,
        )


def _print_policy_project_failure(failure: PolicyProjectValidationFailure) -> None:
    for issue in failure.issues:
        if isinstance(issue, PolicyProjectDiagnostic):
            print(
                f"{failure.manifest_path}:{issue.path}: {issue.code}: {issue.message}",
                file=sys.stderr,
            )
            continue
        source = load_utf8_file(
            failure.manifest_path.parent / issue.primary_span.file_id.value,
            file_id=issue.primary_span.file_id,
        )
        if isinstance(source, SourceLoadFailure):
            print(
                f"{issue.primary_span.file_id.value}@{issue.primary_span.start.value}.."
                f"{issue.primary_span.end.value}: {issue.code}: {issue.message}",
                file=sys.stderr,
            )
            continue
        print(_format_diagnostic(source, issue), file=sys.stderr)


def _validation_files(paths: Sequence[Path]) -> tuple[Path, ...]:
    files: list[Path] = []
    for path in paths:
        if not isinstance(path, Path):
            raise TypeError("validation paths must be paths")
        if path.is_dir():
            files.extend(
                candidate
                for candidate in path.rglob("*")
                if candidate.is_file() and _is_validation_file(candidate)
            )
        else:
            files.append(path)
    return tuple(sorted(set(files), key=lambda candidate: candidate.as_posix()))


def _is_validation_file(path: Path) -> bool:
    return (
        path.name == POLICY_PROJECT_FILENAME
        or path.name.endswith(".dmission.json")
        or path.name.endswith(".kfixture.json")
        or path.suffix == ".dtr"
    )


def _print_selected_query(result: IntentionSelectionExplanation | TraceQueryUnavailable) -> None:
    if isinstance(result, TraceQueryUnavailable):
        _print_unavailable("why-selected", result.code.value)
        return
    print("query: why-selected")
    _print_origin(result.origin)
    print("status: selected")
    _print_resolution_events(result.resolution)


def _print_not_selected_query(
    result: IntentionRejectionExplanation | TraceQueryUnavailable,
) -> None:
    if isinstance(result, TraceQueryUnavailable):
        _print_unavailable("why-not-selected", result.code.value)
        return
    print("query: why-not-selected")
    _print_origin(result.origin)
    print("status: rejected")
    print(f"reason: {result.resolution.reason_code}")
    print(
        "competing_intentions: "
        + _format_ids(
            tuple(identifier.value for identifier in result.resolution.competing_intention_ids)
        )
    )
    _print_resolution_events(result.resolution)


def _print_failed_query(result: IntentionFailureExplanation | TraceQueryUnavailable) -> None:
    if isinstance(result, TraceQueryUnavailable):
        _print_unavailable("why-failed", result.code.value)
        return
    print("query: why-failed")
    _print_origin(result.origin)
    print(
        "failure: "
        f"event={result.failure_event.event_id.value} "
        f"kind={result.failure_event.event_kind.value} "
        f"summary={result.failure_event.summary!r}"
    )
    print("path: " + " -> ".join(str(node_id.value) for node_id in result.path_node_ids))


def _print_consequence_query(
    result: ConsequenceChainExplanation | ConsequenceQueryUnavailable,
) -> None:
    if isinstance(result, ConsequenceQueryUnavailable):
        _print_unavailable("consequence-chain", result.code.value)
        return
    consequence = result.consequence
    print("query: consequence-chain")
    print(
        "consequence: "
        f"node={consequence.node_id.value} "
        f"kind={consequence.kind.value} "
        f"event={consequence.event_id.value} "
        f"summary={consequence.summary!r}"
    )
    print("causes:")
    for record in result.causal_records:
        print(f"  {_format_trace_record(record)}")
    print("causal_edges: " + _format_ids(tuple(edge.edge_id.value for edge in result.causal_edges)))


def _print_unavailable(query_name: str, code: str) -> None:
    print(f"query: {query_name}")
    print(f"unavailable: {code}")


def _print_origin(origin: IntentionOrigin) -> None:
    span = origin.source_span
    print(f"intention: {origin.intention_id.value}")
    print(f"source: {span.file_id.value}@{span.start.value}..{span.end.value}")
    print(f"policy_order: {origin.policy_order}")


def _print_resolution_events(resolution: IntentionResolutionTrace) -> None:
    print(
        "world_events: "
        + _format_ids(tuple(event_id.value for event_id in resolution.world_event_ids))
    )


def _format_ids(values: tuple[int, ...]) -> str:
    return ", ".join(str(value) for value in values) if values else "none"


def _format_trace_record(record: TraceRecord) -> str:
    if isinstance(record, WorldEventTrace):
        return (
            f"node={record.node_id.value} world_event event={record.event_id.value} "
            f"kind={record.event_kind.value} summary={record.summary!r}"
        )
    if isinstance(record, IntentionTrace):
        origin = record.origin
        return (
            f"node={record.node_id.value} intention intention={origin.intention_id.value} "
            f"source={origin.source_span.file_id.value}@{origin.source_span.start.value}.."
            f"{origin.source_span.end.value}"
        )
    if isinstance(record, IntentionResolutionTrace):
        return (
            f"node={record.node_id.value} intention_resolution "
            f"intention={record.intention_id.value} status={record.status.value}"
        )
    if isinstance(record, ConsequenceTrace):
        return (
            f"node={record.node_id.value} consequence kind={record.kind.value} "
            f"event={record.event_id.value} summary={record.summary!r}"
        )
    return f"node={record.node_id.value} {type(record).__name__}"


def _check_and_lower(source: SourceFile) -> LowerResult | None:
    parsed = parse(lex(source))
    if parsed.diagnostics:
        _print_diagnostics(source, parsed.diagnostics)
        return None
    checked = check(resolve(parsed.module))
    if checked.diagnostics:
        _print_diagnostics(source, checked.diagnostics)
        return None
    if checked.module is None:
        raise AssertionError("successful check has no typed module")
    return lower(checked.module)


def _compile_source(path: Path) -> BytecodeModule | None:
    source = _load_source(path)
    if source is None:
        return None
    lowered = _check_and_lower(source)
    if lowered is None:
        return None
    return compile_core(lowered.module, BytecodeHeader(source.file_id))


def _function_id_for_name(module: BytecodeModule, entry_name: str) -> FunctionId | None:
    for entry in module.function_table.entries:
        if entry.name == entry_name:
            return entry.function_id
    return None


def _parse_runtime_argument(text: str) -> RuntimeValue | None:
    if text == "true":
        return BooleanValue(True)
    if text == "false":
        return BooleanValue(False)
    if text == "unit":
        return UnitValue()
    digits = text[1:] if text.startswith("-") else text
    if digits and digits.isascii() and digits.isdecimal() and len(digits) <= MAX_INTEGER_DIGITS:
        return IntegerValue(int(text))
    return None


def _format_runtime_value(value: RuntimeValue) -> str:
    if isinstance(value, IntegerValue):
        return f"Integer({value.value})"
    if isinstance(value, BooleanValue):
        return f"Boolean({str(value.value).lower()})"
    if isinstance(value, UnitValue):
        return "Unit"
    if isinstance(value, StringValue):
        return f"String({value.value!r})"
    if isinstance(value, QuantityValue):
        quantity = value.value
        return (
            f"Quantity({quantity.dimension.value},"
            f"{quantity.value.numerator}/{quantity.value.denominator})"
        )
    if isinstance(value, OptionSomeValue):
        return f"Some({_format_runtime_value(value.value)})"
    if isinstance(value, OptionNoneValue):
        return "None"
    if isinstance(value, ListValue):
        return f"List([{', '.join(_format_runtime_value(item) for item in value.values)}])"
    if isinstance(value, ClosureValue):
        captures = ", ".join(_format_runtime_value(item) for item in value.captures)
        return f"Closure({value.function_id.value}, [{captures}])"
    if isinstance(value, RecordValue):
        fields = ", ".join(
            f"{name}={_format_runtime_value(field_value)}"
            for name, field_value in zip(value.field_names, value.values, strict=True)
        )
        return f"Record({value.type_name}, {{{fields}}})"
    if isinstance(value, IntrinsicValue):
        return f"Intrinsic({value.intrinsic.name})"
    return f"Function({value.function_id.value})"


def _format_diagnostic(source: SourceFile, diagnostic: Diagnostic) -> str:
    """Render one structured diagnostic in a stable command-line form."""
    position = source.position_of(diagnostic.primary_span.start)
    return (
        f"{diagnostic.primary_span.file_id.value}:{position.line}:{position.column}: "
        f"{diagnostic.code}: {diagnostic.message}"
    )


def _print_diagnostics(source: SourceFile, diagnostics: tuple[Diagnostic, ...]) -> None:
    for diagnostic in diagnostics:
        print(_format_diagnostic(source, diagnostic), file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    """Run the Kiwi command-line interface."""
    parser = argparse.ArgumentParser(prog="kiwi")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("doctor")
    parse_parser = subparsers.add_parser("parse")
    parse_parser.add_argument("source", type=Path)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("source", type=Path)
    compile_parser = subparsers.add_parser("compile")
    compile_parser.add_argument("source", type=Path)
    compile_parser.add_argument("--output", "-o", type=Path)
    disassemble_parser = subparsers.add_parser("disassemble")
    disassemble_parser.add_argument("source", type=Path)
    run_policy_parser = subparsers.add_parser("run-policy")
    run_policy_parser.add_argument("source", type=Path)
    run_policy_parser.add_argument("entry")
    run_policy_parser.add_argument("--arg", action="append", default=[])
    benchmark_parser = subparsers.add_parser("benchmark")
    benchmark_parser.add_argument("source", type=Path)
    benchmark_parser.add_argument("fixture", type=Path)
    benchmark_parser.add_argument("--entry", default="choose")
    benchmark_parser.add_argument("--arg", action="append", default=[])
    benchmark_parser.add_argument("--iterations", type=int, default=100)
    benchmark_parser.add_argument("--ticks", type=int, default=60)
    validate_parser = subparsers.add_parser("validate")
    validate_parser.add_argument("paths", type=Path, nargs="+")
    trace_query_parser = subparsers.add_parser("trace-query")
    trace_query_parser.add_argument("trace", type=Path)
    trace_query_parser.add_argument(
        "query",
        choices=("why-selected", "why-not-selected", "why-failed", "consequence-chain"),
    )
    trace_query_parser.add_argument("target_id", type=int)
    replay_record_parser = subparsers.add_parser("replay-record")
    replay_record_parser.add_argument("fixture", type=Path)
    replay_record_parser.add_argument("ticks", type=int)
    replay_record_parser.add_argument("output", type=Path)
    replay_record_parser.add_argument("--application-build", required=True)
    replay_record_parser.add_argument("--simulation-version", required=True)
    replay_verify_parser = subparsers.add_parser("replay-verify")
    replay_verify_parser.add_argument("replay", type=Path)
    replay_inspect_parser = subparsers.add_parser("replay-inspect")
    replay_inspect_parser.add_argument("replay", type=Path)
    replay_compare_parser = subparsers.add_parser("replay-compare")
    replay_compare_parser.add_argument("expected", type=Path)
    replay_compare_parser.add_argument("actual", type=Path)
    arguments = parser.parse_args(argv)
    if arguments.command == "doctor":
        return doctor()
    if arguments.command == "parse":
        return parse_source(arguments.source)
    if arguments.command == "check":
        return check_source(arguments.source)
    if arguments.command == "compile":
        return compile_source(arguments.source, arguments.output)
    if arguments.command == "disassemble":
        return disassemble_source(arguments.source)
    if arguments.command == "benchmark":
        return benchmark(
            arguments.source,
            arguments.fixture,
            arguments.entry,
            arguments.arg,
            arguments.iterations,
            arguments.ticks,
        )
    if arguments.command == "validate":
        return validate_paths(arguments.paths)
    if arguments.command == "trace-query":
        return trace_query(arguments.trace, arguments.query, arguments.target_id)
    if arguments.command == "replay-record":
        return replay_record(
            arguments.fixture,
            arguments.ticks,
            arguments.output,
            arguments.application_build,
            arguments.simulation_version,
        )
    if arguments.command == "replay-verify":
        return replay_verify(arguments.replay)
    if arguments.command == "replay-inspect":
        return replay_inspect(arguments.replay)
    if arguments.command == "replay-compare":
        return replay_compare(arguments.expected, arguments.actual)
    return run_policy_source(arguments.source, arguments.entry, arguments.arg)


if __name__ == "__main__":
    raise SystemExit(main())
