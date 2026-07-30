from __future__ import annotations

import pytest

from kiwi.dsl.bytecode import (
    BYTECODE_VERSION,
    CORE_IR_VERSION,
    SOURCE_LANGUAGE_VERSION,
    BytecodeHeader,
)
from kiwi.dsl.source import SourceFileId


def test_bytecode_header_carries_current_compatibility_versions() -> None:
    header = BytecodeHeader(SourceFileId("policy.dtr"))

    assert header.source_file_id == SourceFileId("policy.dtr")
    assert header.source_language_version == SOURCE_LANGUAGE_VERSION == 1
    assert header.core_ir_version == CORE_IR_VERSION == 1
    assert header.bytecode_version == BYTECODE_VERSION == 1


@pytest.mark.parametrize(
    ("keyword", "value", "message"),
    (
        ("source_language_version", 2, "source language"),
        ("core_ir_version", 2, "core IR"),
        ("bytecode_version", 2, "bytecode"),
        ("bytecode_version", True, "bytecode"),
    ),
)
def test_bytecode_header_rejects_incompatible_versions(
    keyword: str,
    value: int,
    message: str,
) -> None:
    with pytest.raises(ValueError, match=message):
        BytecodeHeader(SourceFileId("policy.dtr"), **{keyword: value})
