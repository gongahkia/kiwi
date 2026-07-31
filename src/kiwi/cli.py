"""Headless command-line entry points."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

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
    IntegerValue,
    QuantityValue,
    RecordValue,
    RuntimeValue,
    StringValue,
    UnitValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId, SourceLoadFailure, load_utf8_file
from kiwi.dsl.vm import run_vm

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
    if isinstance(value, RecordValue):
        fields = ", ".join(
            f"{name}={_format_runtime_value(field_value)}"
            for name, field_value in zip(value.field_names, value.values, strict=True)
        )
        return f"Record({value.type_name}, {{{fields}}})"
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
    return run_policy_source(arguments.source, arguments.entry, arguments.arg)


if __name__ == "__main__":
    raise SystemExit(main())
