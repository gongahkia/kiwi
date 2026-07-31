from __future__ import annotations

from pathlib import Path

from kiwi.dsl.checker import check
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId

EXAMPLE_POLICY = Path(__file__).resolve().parents[2] / "examples" / "policies" / "basic.dtr"
M4_EXAMPLE_POLICY = (
    Path(__file__).resolve().parents[2] / "examples" / "policies" / "m4-language.dtr"
)


def test_first_proof_policy_parses() -> None:
    source = SourceFile(
        SourceFileId("examples/policies/basic.dtr"),
        EXAMPLE_POLICY.read_text(encoding="utf-8"),
    )

    result = parse(lex(source))

    assert result.diagnostics == ()
    assert len(result.module.declarations) == 1


def test_milestone_four_language_example_type_checks() -> None:
    source = SourceFile(
        SourceFileId("examples/policies/m4-language.dtr"),
        M4_EXAMPLE_POLICY.read_text(encoding="utf-8"),
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    assert lower(checked.module).module.definitions[0].name == "choose"
