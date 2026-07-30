from __future__ import annotations

from pathlib import Path

from kiwi.dsl.lexer import lex
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId

EXAMPLE_POLICY = Path(__file__).resolve().parents[2] / "examples" / "policies" / "basic.dtr"


def test_first_proof_policy_parses() -> None:
    source = SourceFile(
        SourceFileId("examples/policies/basic.dtr"),
        EXAMPLE_POLICY.read_text(encoding="utf-8"),
    )

    result = parse(lex(source))

    assert result.diagnostics == ()
    assert len(result.module.declarations) == 1
