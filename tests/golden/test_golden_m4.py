from __future__ import annotations

from pathlib import Path

from pytest import CaptureFixture, MonkeyPatch

from kiwi.cli import check_source
from kiwi.dsl.checker import check
from kiwi.dsl.core_debug import format_lower_result
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId

GOLDEN_ROOT = Path(__file__).parent


def test_full_milestone_four_core_golden_fixture() -> None:
    source_path = GOLDEN_ROOT / "m4" / "mvp.dtr"
    source = SourceFile(SourceFileId(source_path.name), source_path.read_text(encoding="utf-8"))
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    assert format_lower_result(lower(checked.module)) + "\n" == source_path.with_suffix(
        ".core"
    ).read_text(encoding="utf-8")


def test_full_milestone_four_diagnostic_golden_fixture(
    capsys: CaptureFixture[str],
    monkeypatch: MonkeyPatch,
) -> None:
    fixture_directory = GOLDEN_ROOT / "diagnostics"
    monkeypatch.chdir(fixture_directory)

    assert check_source(Path("m4.dtr")) == 1

    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err == Path("m4.diagnostics").read_text(encoding="utf-8")
