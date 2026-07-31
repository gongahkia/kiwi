from __future__ import annotations

import pytest

from kiwi.domain.ids import EntityId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.sim.policy_versions import (
    POLICY_VERSION_DIGEST_BYTES,
    EntityPolicyVersion,
    PolicyVersion,
    PolicyVersionStore,
)


def test_policy_versions_are_entry_specific_and_stored_in_entity_order() -> None:
    artifact = _two_policy_artifact()
    first = PolicyVersion.from_artifact(artifact, FunctionId(0))
    second = PolicyVersion.from_artifact(artifact, FunctionId(1))
    initial = PolicyVersionStore()
    updated = initial.with_version(EntityId(2), second).with_version(EntityId(1), first)

    assert first == PolicyVersion.from_artifact(artifact, FunctionId(0))
    assert first != second
    assert len(first.digest) == POLICY_VERSION_DIGEST_BYTES
    assert tuple(entry.entity_id for entry in updated.entries) == (EntityId(1), EntityId(2))
    assert updated.version_for(EntityId(1)) == first
    assert initial.entries == ()


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: PolicyVersion(b""), "32 bytes"),
        (lambda: EntityPolicyVersion(EntityId(1), object()), "policy version"),  # type: ignore[arg-type]
        (
            lambda: PolicyVersionStore(
                (
                    EntityPolicyVersion(EntityId(2), PolicyVersion(bytes(32))),
                    EntityPolicyVersion(EntityId(1), PolicyVersion(bytes(32))),
                )
            ),
            "entity-ID ordered",
        ),
    ),
)
def test_policy_versions_reject_invalid_canonical_values(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]


def _two_policy_artifact() -> CompiledArtifact:
    source = SourceFile(
        SourceFileId("policy.dtr"),
        "policy first(flag: Bool) -> Bool = flag\npolicy second(flag: Bool) -> Bool = flag\n",
    )
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
