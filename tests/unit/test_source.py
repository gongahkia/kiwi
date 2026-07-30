from __future__ import annotations

from pathlib import Path

import pytest

from kiwi.dsl.source import (
    ByteOffset,
    LineIndex,
    SourceFile,
    SourceFileId,
    SourceLoadErrorCode,
    SourceLoadFailure,
    SourcePosition,
    SourceSpan,
    load_utf8_file,
)


def test_line_index_maps_utf8_byte_boundaries_to_positions() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "aé\nZ")

    assert source.line_index.byte_length == 5
    assert source.position_of(ByteOffset(0)) == SourcePosition(ByteOffset(0), line=1, column=1)
    assert source.position_of(ByteOffset(1)) == SourcePosition(ByteOffset(1), line=1, column=2)
    assert source.position_of(ByteOffset(3)) == SourcePosition(ByteOffset(3), line=1, column=3)
    assert source.position_of(ByteOffset(4)) == SourcePosition(ByteOffset(4), line=2, column=1)
    assert source.position_of(ByteOffset(5)) == SourcePosition(ByteOffset(5), line=2, column=2)


def test_line_index_rejects_out_of_bounds_and_mid_code_point_offsets() -> None:
    index = LineIndex.from_text("é")

    with pytest.raises(ValueError, match="splits a UTF-8 code point"):
        index.position_of(ByteOffset(1))
    with pytest.raises(ValueError, match="outside source"):
        index.position_of(ByteOffset(3))


def test_source_spans_are_half_open_and_file_bound() -> None:
    source = SourceFile(SourceFileId("policy.dtr"), "true")
    span = source.span(ByteOffset(0), ByteOffset(4))

    assert span == SourceSpan(SourceFileId("policy.dtr"), ByteOffset(0), ByteOffset(4))
    assert span.byte_length == 4
    assert span.contains(ByteOffset(0))
    assert span.contains(ByteOffset(3))
    assert not span.contains(ByteOffset(4))
    assert source.positions_of(span) == (
        SourcePosition(ByteOffset(0), line=1, column=1),
        SourcePosition(ByteOffset(4), line=1, column=5),
    )


def test_source_model_rejects_invalid_ids_offsets_and_spans() -> None:
    with pytest.raises(ValueError, match="non-empty string"):
        SourceFileId("")
    with pytest.raises(ValueError, match="non-empty string"):
        SourceFileId(1)  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="non-negative"):
        ByteOffset(-1)
    with pytest.raises(ValueError, match="non-negative"):
        ByteOffset(True)
    with pytest.raises(ValueError, match="non-negative"):
        ByteOffset("0")  # type: ignore[arg-type]
    with pytest.raises(ValueError, match="line and column"):
        SourcePosition(ByteOffset(0), line=0, column=1)
    with pytest.raises(ValueError, match="end precedes"):
        SourceSpan(SourceFileId("policy.dtr"), ByteOffset(2), ByteOffset(1))


def test_source_file_rejects_non_text_input() -> None:
    with pytest.raises(ValueError, match="must be a string"):
        SourceFile(SourceFileId("policy.dtr"), b"true")  # type: ignore[arg-type]


def test_source_file_rejects_spans_from_another_file() -> None:
    first = SourceFile(SourceFileId("first.dtr"), "x")
    second = SourceFile(SourceFileId("second.dtr"), "x")

    with pytest.raises(ValueError, match="different source file"):
        first.positions_of(second.span(ByteOffset(0), ByteOffset(1)))


def test_load_utf8_file_returns_source_file_at_the_filesystem_boundary(tmp_path: Path) -> None:
    path = tmp_path / "policy.dtr"
    path.write_bytes("é".encode())

    loaded = load_utf8_file(path, file_id=SourceFileId("policy.dtr"), max_bytes=2)

    assert loaded == SourceFile(SourceFileId("policy.dtr"), "é")


def test_load_utf8_file_reports_size_and_encoding_failures(tmp_path: Path) -> None:
    too_large_path = tmp_path / "large.dtr"
    too_large_path.write_bytes(b"true")
    invalid_utf8_path = tmp_path / "invalid.dtr"
    invalid_utf8_path.write_bytes(b"\xff")

    too_large = load_utf8_file(too_large_path, file_id=SourceFileId("large.dtr"), max_bytes=3)
    invalid_utf8 = load_utf8_file(
        invalid_utf8_path,
        file_id=SourceFileId("invalid.dtr"),
        max_bytes=1,
    )

    assert too_large == SourceLoadFailure(
        SourceLoadErrorCode.TOO_LARGE,
        SourceFileId("large.dtr"),
        "source exceeds the configured byte limit",
    )
    assert invalid_utf8 == SourceLoadFailure(
        SourceLoadErrorCode.INVALID_UTF8,
        SourceFileId("invalid.dtr"),
        "source is not valid UTF-8",
    )


def test_load_utf8_file_reports_read_and_limit_failures(tmp_path: Path) -> None:
    missing = load_utf8_file(tmp_path / "missing.dtr", file_id=SourceFileId("missing.dtr"))

    assert missing == SourceLoadFailure(
        SourceLoadErrorCode.READ_FAILED,
        SourceFileId("missing.dtr"),
        "could not read source",
    )
    with pytest.raises(ValueError, match="byte limit"):
        load_utf8_file(tmp_path / "missing.dtr", file_id=SourceFileId("missing.dtr"), max_bytes=-1)
