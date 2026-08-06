from __future__ import annotations

import pytest

from kiwi.domain.ids import EventId
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import EventHeader, LockdownActivated, MissionStarted
from kiwi.sim.scheduled import ScheduledEvent, ScheduledEventKind
from kiwi.ui.terminal_mission import (
    TerminalSoundCue,
    TerminalSoundCueKind,
    build_terminal_sound_cues,
)


def test_terminal_sound_cues_copy_only_audible_canonical_events() -> None:
    trigger_id = EventId(1)
    started = MissionStarted(
        EventHeader(trigger_id, 0),
        StartMission(CommandHeader(0, 0, CommandSource.PLAYER)),
    )
    lockdown = LockdownActivated(
        EventHeader(EventId(2), 0, (trigger_id,)),
        ScheduledEvent(0, 0, ScheduledEventKind.LOCKDOWN),
    )

    assert build_terminal_sound_cues((started, lockdown)) == (
        TerminalSoundCue(2, TerminalSoundCueKind.LOCKDOWN),
    )


def test_terminal_sound_cues_reject_noncanonical_input() -> None:
    with pytest.raises(TypeError, match="immutable canonical events"):
        build_terminal_sound_cues([])  # type: ignore[arg-type]
