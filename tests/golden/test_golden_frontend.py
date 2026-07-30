from __future__ import annotations

from pathlib import Path

from kiwi.dsl.debug import format_surface_module, format_tokens
from kiwi.dsl.lexer import lex
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId

GOLDEN_ROOT = Path(__file__).parent


def source_from_fixture(path: Path) -> SourceFile:
    return SourceFile(SourceFileId(path.name), path.read_text(encoding="utf-8"))


def test_lexer_golden_fixture() -> None:
    source_path = GOLDEN_ROOT / "lexer" / "basic.dtr"
    expected_path = source_path.with_suffix(".tokens")

    actual = format_tokens(lex(source_from_fixture(source_path)).tokens)

    assert actual + "\n" == expected_path.read_text(encoding="utf-8")


def test_parser_golden_fixture() -> None:
    source_path = GOLDEN_ROOT / "parser" / "basic.dtr"
    expected_path = source_path.with_suffix(".ast")
    parsed = parse(lex(source_from_fixture(source_path)))

    assert parsed.diagnostics == ()
    assert format_surface_module(parsed.module) + "\n" == expected_path.read_text(encoding="utf-8")
