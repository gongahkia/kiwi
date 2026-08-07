"""Terminal policy-source adapter for the briefing and workbench flow."""

from __future__ import annotations

from kiwi.app.terminal_players import TERMINAL_PLAYER_LOADOUTS
from kiwi.dsl.source import SourceFile
from kiwi.ui.terminal_workbench import (
    TerminalWorkbench,
    WorkbenchPolicy,
    create_terminal_workbench,
)


def build_terminal_workbench(policy_sources: tuple[SourceFile, ...]) -> TerminalWorkbench:
    """Bind the canonical player roster's loaded sources to immutable UI state."""
    if not isinstance(policy_sources, tuple) or len(policy_sources) != len(
        TERMINAL_PLAYER_LOADOUTS
    ):
        raise ValueError("Terminal workbench requires four immutable policy sources")
    policies: list[WorkbenchPolicy] = []
    for loadout, source in zip(TERMINAL_PLAYER_LOADOUTS, policy_sources, strict=True):
        if not isinstance(source, SourceFile):
            raise TypeError("Terminal workbench policies must be source files")
        if source.file_id.value != loadout.policy_file_id:
            raise ValueError("Terminal workbench sources must match the canonical roster")
        policies.append(WorkbenchPolicy(loadout.role.value, loadout.callsign, source))
    return create_terminal_workbench(tuple(policies))


def build_terminal_practice_workbench(policy_sources: tuple[SourceFile, ...]) -> TerminalWorkbench:
    """Bind one authored practice bundle while retaining Terminal's fixed role order."""
    if not isinstance(policy_sources, tuple) or len(policy_sources) != len(
        TERMINAL_PLAYER_LOADOUTS
    ):
        raise ValueError("Terminal practice workbench requires four immutable policy sources")
    policies: list[WorkbenchPolicy] = []
    for loadout, source in zip(TERMINAL_PLAYER_LOADOUTS, policy_sources, strict=True):
        if not isinstance(source, SourceFile):
            raise TypeError("Terminal practice policies must be source files")
        policies.append(WorkbenchPolicy(loadout.role.value, loadout.callsign, source))
    return create_terminal_workbench(tuple(policies))
