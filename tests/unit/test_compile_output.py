from __future__ import annotations

from kiwi.dsl.source import SourceFileId
from kiwi.ui.compile_output import compile_editor_source
from kiwi.ui.editor import EditorState


def test_workbench_compile_returns_source_bound_bytecode_metadata_without_editor_mutation() -> None:
    editor = EditorState.from_text("fn choose(value: Int) -> Int = value")

    output = compile_editor_source(SourceFileId("workbench.dtr"), editor)

    assert output.succeeded
    assert output.artifact is not None
    assert output.diagnostics is None
    assert output.encoded_byte_count is not None
    assert output.source.file_id == SourceFileId("workbench.dtr")
    assert output.source.text == editor.buffer.text
    assert output.artifact.bytecode.header.source_file_id == output.source.file_id
    assert output.panel_lines[0] == "compile: success"
    assert output.panel_lines[1].startswith("bytecode: KWI-BC v2 ")
    assert output.panel_lines[2] == "functions: 1"
    assert editor.buffer.text == "fn choose(value: Int) -> Int = value"


def test_workbench_compile_returns_structured_source_bound_diagnostics_on_failure() -> None:
    output = compile_editor_source(SourceFileId("broken.dtr"), EditorState.from_text("@"))

    assert not output.succeeded
    assert output.artifact is None
    assert output.encoded_byte_count is None
    assert output.diagnostics is not None
    assert output.diagnostics.source_file_id == SourceFileId("broken.dtr")
    assert output.diagnostics.panel[0].diagnostic.code == "E100_INVALID_CHARACTER"
    assert output.panel_lines == ("compile: failed (1 diagnostic)",)
