"""Headless workbench compilation and immutable output-panel data."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.bytecode_codec import encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.diagnostics import Diagnostic
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.ui.diagnostics import DiagnosticPresentation, present_diagnostics
from kiwi.ui.editor import EditorState


@dataclass(frozen=True, slots=True)
class CompileOutput:
    """One source-matched compiler outcome for the non-authoritative workbench."""

    source: SourceFile
    artifact: CompiledArtifact | None
    encoded_byte_count: int | None
    diagnostics: DiagnosticPresentation | None

    def __post_init__(self) -> None:
        if not isinstance(self.source, SourceFile):
            raise TypeError("compile output requires a source file")
        if self.artifact is not None:
            if self.diagnostics is not None:
                raise ValueError("successful compile output must not retain diagnostics")
            if not isinstance(self.encoded_byte_count, int) or self.encoded_byte_count < 0:
                raise ValueError("successful compile output requires a byte count")
            if self.artifact.bytecode.header.source_file_id != self.source.file_id:
                raise ValueError("compiled bytecode source does not match compile output")
        elif self.encoded_byte_count is not None:
            raise ValueError("failed compile output must not retain a byte count")
        elif self.diagnostics is None:
            raise ValueError("failed compile output requires diagnostic presentation")
        elif self.diagnostics.source_file_id != self.source.file_id:
            raise ValueError("compile diagnostics source does not match compile output")

    @property
    def succeeded(self) -> bool:
        """Return whether the source completed every compiler stage."""
        return self.artifact is not None

    @property
    def panel_lines(self) -> tuple[str, ...]:
        """Return deterministic concise status rows for the compile output panel."""
        if not self.succeeded:
            if self.diagnostics is None:
                raise AssertionError("failed compile output has no diagnostics")
            count = len(self.diagnostics.panel)
            suffix = "diagnostic" if count == 1 else "diagnostics"
            return (f"compile: failed ({count} {suffix})",)
        if self.artifact is None or self.encoded_byte_count is None:
            raise AssertionError("successful compile output has incomplete artifact metadata")
        bytecode = self.artifact.bytecode
        instruction_count = sum(len(function.instructions) for function in bytecode.functions)
        return (
            "compile: success",
            f"bytecode: KWI-BC v{bytecode.header.bytecode_version} {self.encoded_byte_count} bytes",
            f"functions: {len(bytecode.functions)}",
            f"instructions: {instruction_count}",
            f"capability entries: {len(self.artifact.capability_manifest.entries)}",
        )


def compile_editor_source(source_file_id: SourceFileId, editor: EditorState) -> CompileOutput:
    """Compile immutable editor text through the closed DSL pipeline without UI mutation."""
    if not isinstance(source_file_id, SourceFileId):
        raise TypeError("workbench compile source ID must be a source file ID")
    if not isinstance(editor, EditorState):
        raise TypeError("workbench compile requires an editor state")
    source = SourceFile(source_file_id, editor.buffer.text)
    parsed = parse(lex(source))
    if parsed.diagnostics:
        return _failed_output(source, parsed.diagnostics)
    resolved = resolve(parsed.module)
    if resolved.diagnostics:
        return _failed_output(source, resolved.diagnostics)
    checked = check(resolved)
    if checked.diagnostics:
        return _failed_output(source, checked.diagnostics)
    if checked.module is None:
        raise AssertionError("diagnostic-free check has no typed module")
    artifact = compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
    return CompileOutput(source, artifact, len(encode_bytecode(artifact.bytecode)), None)


def _failed_output(source: SourceFile, diagnostics: tuple[Diagnostic, ...]) -> CompileOutput:
    return CompileOutput(source, None, None, present_diagnostics(source, diagnostics))
