"""Glasshouse policy-source adapter for the briefing and workbench flow."""

from __future__ import annotations

from kiwi.app.glasshouse_players import GLASSHOUSE_PLAYER_LOADOUTS
from kiwi.dsl.source import SourceFile
from kiwi.ui.glasshouse_workbench import (
    GlasshouseWorkbench,
    WorkbenchPolicy,
    create_glasshouse_workbench,
)


def build_glasshouse_workbench(policy_sources: tuple[SourceFile, ...]) -> GlasshouseWorkbench:
    """Bind the canonical player roster's loaded sources to immutable UI state."""
    if not isinstance(policy_sources, tuple) or len(policy_sources) != len(
        GLASSHOUSE_PLAYER_LOADOUTS
    ):
        raise ValueError("Glasshouse workbench requires four immutable policy sources")
    policies: list[WorkbenchPolicy] = []
    for loadout, source in zip(GLASSHOUSE_PLAYER_LOADOUTS, policy_sources, strict=True):
        if not isinstance(source, SourceFile):
            raise TypeError("Glasshouse workbench policies must be source files")
        if source.file_id.value != loadout.policy_file_id:
            raise ValueError("Glasshouse workbench sources must match the canonical roster")
        policies.append(WorkbenchPolicy(loadout.role.value, loadout.callsign, source))
    return create_glasshouse_workbench(tuple(policies))
