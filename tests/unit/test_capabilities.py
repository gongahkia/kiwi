from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.capabilities import (
    AIM_CAPABILITY,
    CAPABILITY_MANIFEST_VERSION,
    FIRE_CAPABILITY,
    MOVE_TOWARD_CAPABILITY,
    TAKE_COVER_CAPABILITY,
    WAIT_CAPABILITY,
    CapabilityId,
    CapabilityManifest,
    CapabilityRequirement,
    EntryPointCapabilities,
)
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_artifact, compile_core
from kiwi.dsl.core_ir import CoreModule
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId


def test_compiled_artifact_has_canonical_empty_manifest_for_policy_entries() -> None:
    source = SourceFile(
        SourceFileId("capabilities.dtr"),
        "fn helper() -> Int = 1\n"
        "policy beta() -> Int = helper()\n"
        "policy alpha() -> Int = helper()\n",
    )
    core = _core(source)

    first = compile_artifact(core, BytecodeHeader(source.file_id))
    second = compile_artifact(core, BytecodeHeader(source.file_id))

    assert first == second
    assert first.bytecode == compile_core(core, BytecodeHeader(source.file_id))
    assert first.capability_manifest == CapabilityManifest(
        CAPABILITY_MANIFEST_VERSION,
        (
            EntryPointCapabilities(FunctionId(1), "beta"),
            EntryPointCapabilities(FunctionId(2), "alpha"),
        ),
    )
    assert decode_bytecode(encode_bytecode(first.bytecode)) == first.bytecode


def test_capability_manifest_values_are_versioned_canonical_and_source_linked() -> None:
    source = SourceFile(SourceFileId("capability-values.dtr"), "policy step() -> Int = 1")
    span = source.span(ByteOffset(0), ByteOffset(6))
    movement = CapabilityRequirement(CapabilityId("movement"), span)
    targeting = CapabilityRequirement(CapabilityId("targeting"), span)

    entry = EntryPointCapabilities(FunctionId(0), "step", (movement, targeting))

    assert entry.requirements == (movement, targeting)
    with pytest.raises(ValueError, match="lowercase ASCII"):
        CapabilityId("Move")
    with pytest.raises(ValueError, match="lexically ordered"):
        EntryPointCapabilities(FunctionId(0), "step", (targeting, movement))
    with pytest.raises(ValueError, match="unsupported"):
        CapabilityManifest(2, ())
    with pytest.raises(ValueError, match="function-ID ordered"):
        CapabilityManifest(
            CAPABILITY_MANIFEST_VERSION,
            (
                EntryPointCapabilities(FunctionId(1), "two"),
                EntryPointCapabilities(FunctionId(0), "one"),
            ),
        )


def test_compiler_records_wait_requirement_at_its_source_construction() -> None:
    source = SourceFile(
        SourceFileId("wait-capability.dtr"),
        "type Wait = { duration: Duration }\npolicy decide() -> Wait = Wait { duration = 1s }\n",
    )

    artifact = compile_artifact(_core(source), BytecodeHeader(source.file_id))
    requirement = artifact.capability_manifest.entries[0].requirements[0]
    wait_start = source.text.index("Wait { duration")

    assert requirement.capability == WAIT_CAPABILITY
    assert requirement.primary_span == source.span(
        ByteOffset(wait_start), ByteOffset(wait_start + len("Wait { duration = 1s }"))
    )


def test_compiler_records_move_toward_requirement_at_its_source_construction() -> None:
    source = SourceFile(
        SourceFileId("move-capability.dtr"),
        "type MoveToward = { target: Position }\n"
        "policy decide() -> MoveToward = "
        "MoveToward { target = Position { x = 1m, y = 2m } }\n",
    )

    artifact = compile_artifact(_core(source), BytecodeHeader(source.file_id))
    requirement = artifact.capability_manifest.entries[0].requirements[0]
    move_text = "MoveToward { target = Position { x = 1m, y = 2m } }"
    move_start = source.text.index(move_text)

    assert requirement.capability == MOVE_TOWARD_CAPABILITY
    assert requirement.primary_span == source.span(
        ByteOffset(move_start), ByteOffset(move_start + len(move_text))
    )


def test_compiler_records_take_cover_requirement_at_its_source_construction() -> None:
    source = SourceFile(
        SourceFileId("take-cover-capability.dtr"),
        "type TakeCover = { cover_id: Int, side: String }\n"
        'policy decide() -> TakeCover = TakeCover { cover_id = 1, side = "left" }\n',
    )

    artifact = compile_artifact(_core(source), BytecodeHeader(source.file_id))
    requirement = artifact.capability_manifest.entries[0].requirements[0]
    take_cover_text = 'TakeCover { cover_id = 1, side = "left" }'
    take_cover_start = source.text.index(take_cover_text)

    assert requirement.capability == TAKE_COVER_CAPABILITY
    assert requirement.primary_span == source.span(
        ByteOffset(take_cover_start),
        ByteOffset(take_cover_start + len(take_cover_text)),
    )


def test_compiler_records_fire_requirement_at_its_source_construction() -> None:
    source = SourceFile(
        SourceFileId("fire-capability.dtr"),
        "type Fire = { target: Position, weapon_id: Int }\n"
        "policy decide() -> Fire = "
        "Fire { target = Position { x = 1m, y = 2m }, weapon_id = 1 }\n",
    )

    artifact = compile_artifact(_core(source), BytecodeHeader(source.file_id))
    requirement = artifact.capability_manifest.entries[0].requirements[0]
    fire_text = "Fire { target = Position { x = 1m, y = 2m }, weapon_id = 1 }"
    fire_start = source.text.index(fire_text)

    assert requirement.capability == FIRE_CAPABILITY
    assert requirement.primary_span == source.span(
        ByteOffset(fire_start), ByteOffset(fire_start + len(fire_text))
    )


def test_compiler_records_aim_requirement_at_its_source_construction() -> None:
    source = SourceFile(
        SourceFileId("aim-capability.dtr"),
        "type Aim = {}\npolicy decide() -> Aim = Aim {}\n",
    )

    artifact = compile_artifact(_core(source), BytecodeHeader(source.file_id))
    requirement = artifact.capability_manifest.entries[0].requirements[0]
    aim_text = "Aim {}"
    aim_start = source.text.index(aim_text)

    assert requirement.capability == AIM_CAPABILITY
    assert requirement.primary_span == source.span(
        ByteOffset(aim_start), ByteOffset(aim_start + len(aim_text))
    )


def test_compiler_records_take_cover_requirement_at_cover_helper_invocation() -> None:
    source = SourceFile(
        SourceFileId("take-cover-helper-capability.dtr"),
        "type TakeCover = { cover_id: Int, side: String }\n"
        'policy decide() -> TakeCover = Cover.seek(1, "left")\n',
    )

    artifact = compile_artifact(_core(source), BytecodeHeader(source.file_id))
    requirement = artifact.capability_manifest.entries[0].requirements[0]
    helper_text = 'Cover.seek(1, "left")'
    helper_start = source.text.index(helper_text)

    assert requirement.capability == TAKE_COVER_CAPABILITY
    assert requirement.primary_span == source.span(
        ByteOffset(helper_start),
        ByteOffset(helper_start + len(helper_text)),
    )


def _core(source: SourceFile) -> CoreModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.diagnostics == ()
    assert checked.module is not None
    return lower(checked.module).module
