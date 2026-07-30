from __future__ import annotations

from pathlib import Path

from kiwi.dsl.checker import check
from kiwi.dsl.core_debug import format_lower_result
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId

GOLDEN_ROOT = Path(__file__).parent / "core"


def test_core_golden_fixture() -> None:
    source_path = GOLDEN_ROOT / "basic.dtr"
    source = SourceFile(SourceFileId("basic.dtr"), source_path.read_text(encoding="utf-8"))
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    assert format_lower_result(lower(checked.module)) == (GOLDEN_ROOT / "basic.core").read_text(
        encoding="utf-8"
    ).rstrip("\n")
