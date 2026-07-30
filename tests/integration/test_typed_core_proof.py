from __future__ import annotations

from pathlib import Path

from kiwi.dsl.checker import check
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId

EXAMPLE_POLICY = Path(__file__).resolve().parents[2] / "examples" / "policies" / "typed_core.dtr"


def test_typed_core_proof_policy_lowers_successfully() -> None:
    source = SourceFile(
        SourceFileId("examples/policies/typed_core.dtr"),
        EXAMPLE_POLICY.read_text(encoding="utf-8"),
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    core = lower(checked.module)
    assert tuple(definition.name for definition in core.module.definitions) == (
        "identity",
        "choose",
    )
    assert len(core.source_map.entries) == 7
