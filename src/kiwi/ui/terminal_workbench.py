"""Immutable Terminal briefing and multi-policy workbench presentation state."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.dsl.source import SourceFile, SourceSpan
from kiwi.ui.compile_output import CompileOutput, compile_editor_source
from kiwi.ui.editor import EditorState, ScrollPosition, TextPosition

TERMINAL_POLICY_ROLES = ("breacher", "medic", "overwatch", "scout")


class TerminalFlowPhase(StrEnum):
    """The two non-authoritative pre-mission Terminal presentation phases."""

    BRIEFING = "briefing"
    WORKBENCH = "workbench"


@dataclass(frozen=True, slots=True)
class TerminalBriefing:
    """Fixed mission information shown before policy editing begins."""

    title: str
    primary_objective: str
    time_limit: str
    intelligence: tuple[str, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.title, str) or not self.title:
            raise ValueError("Terminal briefing title must be text")
        if not isinstance(self.primary_objective, str) or not self.primary_objective:
            raise ValueError("Terminal briefing objective must be text")
        if not isinstance(self.time_limit, str) or not self.time_limit:
            raise ValueError("Terminal briefing time limit must be text")
        if not isinstance(self.intelligence, tuple) or not self.intelligence:
            raise ValueError(
                "Terminal briefing intelligence must be an immutable non-empty tuple"
            )
        if any(not isinstance(item, str) or not item for item in self.intelligence):
            raise ValueError("Terminal briefing intelligence must contain text")

    @property
    def panel_lines(self) -> tuple[str, ...]:
        """Return fixed concise rows suitable for the bitmap briefing panel."""
        return (
            self.title,
            "",
            "PRIMARY OBJECTIVE",
            self.primary_objective,
            "",
            "TIME PRESSURE",
            self.time_limit,
            "",
            "INTELLIGENCE",
            *self.intelligence,
            "",
            "OPEN KIWI WORKBENCH",
        )


TERMINAL_BRIEFING = TerminalBriefing(
    "TERMINAL",
    "Recover the protected objective, then extract.",
    "Extraction locks exactly 90 seconds after mission start.",
    (
        "Hostile intelligence is incomplete.",
        "Lark begins with one 0.5m-uncertainty contact.",
        "Review each policy before deployment.",
    ),
)


@dataclass(frozen=True, slots=True)
class WorkbenchPolicy:
    """One fixed squad role and the closed-DSL source it may edit."""

    role: str
    callsign: str
    source: SourceFile

    def __post_init__(self) -> None:
        if not isinstance(self.role, str) or self.role not in TERMINAL_POLICY_ROLES:
            raise ValueError("Terminal workbench policy requires a canonical role")
        if not isinstance(self.callsign, str) or not self.callsign:
            raise ValueError("Terminal workbench policy callsign must be text")
        if not isinstance(self.source, SourceFile):
            raise TypeError("Terminal workbench policy requires source")

    @property
    def label(self) -> str:
        """Return the compact deterministic sidebar label."""
        return f"{self.callsign} / {self.role}"


@dataclass(frozen=True, slots=True)
class TerminalWorkbench:
    """Briefing-to-editor state without filesystem or authority mutation."""

    phase: TerminalFlowPhase
    briefing: TerminalBriefing
    policies: tuple[WorkbenchPolicy, ...]
    selected_policy_index: int
    editors: tuple[EditorState, ...]
    compile_outputs: tuple[CompileOutput | None, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.phase, TerminalFlowPhase):
            raise TypeError("Terminal workbench phase is invalid")
        if not isinstance(self.briefing, TerminalBriefing):
            raise TypeError("Terminal workbench briefing is invalid")
        _validate_policies(self.policies)
        if (
            not isinstance(self.selected_policy_index, int)
            or isinstance(self.selected_policy_index, bool)
            or not 0 <= self.selected_policy_index < len(self.policies)
        ):
            raise ValueError("Terminal workbench selection is invalid")
        if not isinstance(self.editors, tuple) or len(self.editors) != len(self.policies):
            raise ValueError("Terminal workbench requires one editor per policy")
        if any(not isinstance(editor, EditorState) for editor in self.editors):
            raise TypeError("Terminal workbench editors are invalid")
        if not isinstance(self.compile_outputs, tuple) or len(self.compile_outputs) != len(
            self.policies
        ):
            raise ValueError("Terminal workbench requires one compile output per policy")
        for policy, editor, output in zip(
            self.policies, self.editors, self.compile_outputs, strict=True
        ):
            if output is not None and not isinstance(output, CompileOutput):
                raise TypeError("Terminal workbench compile output is invalid")
            if output is not None and output.source.text != editor.buffer.text:
                raise ValueError("Terminal workbench compile output is stale")
            if output is not None and output.source.file_id != policy.source.file_id:
                raise ValueError("Terminal workbench compile output source is invalid")

    @property
    def selected_policy(self) -> WorkbenchPolicy:
        """Return the selected immutable role policy."""
        return self.policies[self.selected_policy_index]

    @property
    def editor(self) -> EditorState:
        """Return the selected role's independent editor state."""
        return self.editors[self.selected_policy_index]

    @property
    def compile_output(self) -> CompileOutput | None:
        """Return the selected role's current compile outcome, if any."""
        return self.compile_outputs[self.selected_policy_index]

    @property
    def source(self) -> SourceFile:
        """Return current selected editor text with its fixed source identity."""
        return self.sources[self.selected_policy_index]

    @property
    def sources(self) -> tuple[SourceFile, ...]:
        """Return every current editor buffer with its fixed source identity."""
        return tuple(
            SourceFile(policy.source.file_id, editor.buffer.text)
            for policy, editor in zip(self.policies, self.editors, strict=True)
        )

    def open_workbench(self) -> TerminalWorkbench:
        """Advance once from briefing to non-authoritative source review."""
        if self.phase is not TerminalFlowPhase.BRIEFING:
            raise ValueError("Terminal workbench is already open")
        return replace(self, phase=TerminalFlowPhase.WORKBENCH)

    def select_policy(self, role: str) -> TerminalWorkbench:
        """Select one canonical squad policy without altering its editor state."""
        if self.phase is not TerminalFlowPhase.WORKBENCH:
            raise ValueError("Terminal briefing must be completed before selecting a policy")
        if not isinstance(role, str):
            raise TypeError("Terminal policy role must be text")
        for index, policy in enumerate(self.policies):
            if policy.role == role:
                return replace(self, selected_policy_index=index)
        raise ValueError("Terminal policy role is unavailable")

    def replace_editor(self, editor: EditorState) -> TerminalWorkbench:
        """Replace only the selected source state and invalidate its prior result."""
        if self.phase is not TerminalFlowPhase.WORKBENCH:
            raise ValueError("Terminal briefing must be completed before editing")
        if not isinstance(editor, EditorState):
            raise TypeError("Terminal workbench editor is invalid")
        return replace(
            self,
            editors=_replace_at(self.editors, self.selected_policy_index, editor),
            compile_outputs=_replace_at(self.compile_outputs, self.selected_policy_index, None),
        )

    def focus_source(self, span: SourceSpan | None) -> TerminalWorkbench:
        """Select an unchanged current-source span without invalidating compilation."""
        if self.phase is not TerminalFlowPhase.WORKBENCH:
            raise ValueError("Terminal briefing must be completed before source navigation")
        if span is not None and not isinstance(span, SourceSpan):
            raise TypeError("Terminal source navigation span is invalid")
        if span is None:
            editor = self.editor.move_cursor(0).scroll_to(ScrollPosition())
        else:
            start, end = self.source.positions_of(span)
            start_offset = self.editor.buffer.offset_of(TextPosition(start.line, start.column))
            end_offset = self.editor.buffer.offset_of(TextPosition(end.line, end.column))
            editor = self.editor.select(start_offset, end_offset).scroll_to(
                ScrollPosition(start.line, start.column)
            )
        return replace(self, editors=_replace_at(self.editors, self.selected_policy_index, editor))

    def compile_selected(self) -> TerminalWorkbench:
        """Compile only selected closed-DSL editor text without deploying it."""
        if self.phase is not TerminalFlowPhase.WORKBENCH:
            raise ValueError("Terminal briefing must be completed before compilation")
        output = compile_editor_source(self.source.file_id, self.editor)
        return replace(
            self,
            compile_outputs=_replace_at(self.compile_outputs, self.selected_policy_index, output),
        )


def create_terminal_workbench(
    policies: tuple[WorkbenchPolicy, ...],
    briefing: TerminalBriefing = TERMINAL_BRIEFING,
) -> TerminalWorkbench:
    """Create the fixed briefing-first flow with isolated editors per squad role."""
    _validate_policies(policies)
    if not isinstance(briefing, TerminalBriefing):
        raise TypeError("Terminal workbench briefing is invalid")
    return TerminalWorkbench(
        TerminalFlowPhase.BRIEFING,
        briefing,
        policies,
        0,
        tuple(EditorState.from_text(policy.source.text) for policy in policies),
        (None,) * len(policies),
    )


def _validate_policies(policies: tuple[WorkbenchPolicy, ...]) -> None:
    if not isinstance(policies, tuple) or len(policies) != len(TERMINAL_POLICY_ROLES):
        raise ValueError("Terminal workbench requires four immutable policies")
    if any(not isinstance(policy, WorkbenchPolicy) for policy in policies):
        raise TypeError("Terminal workbench policies are invalid")
    roles = tuple(policy.role for policy in policies)
    if roles != TERMINAL_POLICY_ROLES:
        raise ValueError("Terminal workbench policies must use canonical role order")
    file_ids = tuple(policy.source.file_id for policy in policies)
    if len(set(file_ids)) != len(file_ids):
        raise ValueError("Terminal workbench policy sources must be unique")


def _replace_at[T](values: tuple[T, ...], index: int, value: T) -> tuple[T, ...]:
    return (*values[:index], value, *values[index + 1 :])
