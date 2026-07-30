"""Headless command-line entry points."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from pathlib import Path

from kiwi.dsl.checker import check
from kiwi.dsl.core_debug import format_lower_result
from kiwi.dsl.debug import format_surface_module
from kiwi.dsl.diagnostics import Diagnostic
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId, SourceLoadFailure, load_utf8_file

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
    source_or_failure = load_utf8_file(path, file_id=SourceFileId(str(path)))
    if isinstance(source_or_failure, SourceLoadFailure):
        print(
            f"{source_or_failure.file_id.value}: {source_or_failure.code}: "
            f"{source_or_failure.message}",
            file=sys.stderr,
        )
        return 1
    source = source_or_failure
    result = parse(lex(source))
    if result.diagnostics:
        for diagnostic in result.diagnostics:
            print(_format_diagnostic(source, diagnostic), file=sys.stderr)
        return 1
    print(format_surface_module(result.module))
    return 0


def check_source(path: Path) -> int:
    """Type-check and lower one source file without importing pygame."""
    source_or_failure = load_utf8_file(path, file_id=SourceFileId(str(path)))
    if isinstance(source_or_failure, SourceLoadFailure):
        print(
            f"{source_or_failure.file_id.value}: {source_or_failure.code}: "
            f"{source_or_failure.message}",
            file=sys.stderr,
        )
        return 1
    source = source_or_failure
    parsed = parse(lex(source))
    if parsed.diagnostics:
        _print_diagnostics(source, parsed.diagnostics)
        return 1
    checked = check(resolve(parsed.module))
    if checked.diagnostics:
        _print_diagnostics(source, checked.diagnostics)
        return 1
    if checked.module is None:
        raise AssertionError("successful check has no typed module")
    print(format_lower_result(lower(checked.module)))
    return 0


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
    arguments = parser.parse_args(argv)
    if arguments.command == "doctor":
        return doctor()
    if arguments.command == "parse":
        return parse_source(arguments.source)
    return check_source(arguments.source)


if __name__ == "__main__":
    raise SystemExit(main())
