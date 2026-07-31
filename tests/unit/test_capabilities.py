from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.capabilities import (
    CAPABILITY_MANIFEST_VERSION,
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


def _core(source: SourceFile) -> CoreModule:
    checked = check(resolve(parse(lex(source)).module))
    assert checked.diagnostics == ()
    assert checked.module is not None
    return lower(checked.module).module
