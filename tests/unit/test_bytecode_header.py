from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import (
    BYTECODE_VERSION,
    CORE_IR_VERSION,
    LEGACY_BYTECODE_VERSION,
    LEGACY_CORE_IR_VERSION,
    LEGACY_SOURCE_LANGUAGE_VERSION,
    SOURCE_LANGUAGE_VERSION,
    BytecodeHeader,
)
from kiwi.dsl.source import SourceFileId


def test_bytecode_header_carries_current_compatibility_versions() -> None:
    header = BytecodeHeader(SourceFileId("policy.dtr"))

    assert header.source_file_id == SourceFileId("policy.dtr")
    assert header.source_language_version == SOURCE_LANGUAGE_VERSION == 2
    assert header.core_ir_version == CORE_IR_VERSION == 2
    assert header.bytecode_version == BYTECODE_VERSION == 2


def test_bytecode_header_accepts_explicit_legacy_version_one() -> None:
    header = BytecodeHeader(
        SourceFileId("legacy.dtr"),
        LEGACY_SOURCE_LANGUAGE_VERSION,
        LEGACY_CORE_IR_VERSION,
        LEGACY_BYTECODE_VERSION,
    )

    assert header.source_language_version == 1
    assert header.core_ir_version == 1
    assert header.bytecode_version == 1


@pytest.mark.parametrize(
    ("keyword", "value", "message"),
    (
        ("source_language_version", 1, "compatibility"),
        ("core_ir_version", 1, "compatibility"),
        ("bytecode_version", 1, "compatibility"),
        ("bytecode_version", True, "versions"),
    ),
)
def test_bytecode_header_rejects_incompatible_versions(
    keyword: str,
    value: int,
    message: str,
) -> None:
    with pytest.raises(ValueError, match=message):
        BytecodeHeader(SourceFileId("policy.dtr"), **{keyword: value})
