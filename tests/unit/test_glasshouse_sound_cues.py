from __future__ import annotations

import pytest

from kiwi.domain.ids import EventId
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import EventHeader, LockdownActivated, MissionStarted
from kiwi.sim.scheduled import ScheduledEvent, ScheduledEventKind
from kiwi.ui.glasshouse_mission import (
    GlasshouseSoundCue,
    GlasshouseSoundCueKind,
    build_glasshouse_sound_cues,
)


def test_glasshouse_sound_cues_copy_only_audible_canonical_events() -> None:
    trigger_id = EventId(1)
    started = MissionStarted(
        EventHeader(trigger_id, 0),
        StartMission(CommandHeader(0, 0, CommandSource.PLAYER)),
    )
    lockdown = LockdownActivated(
        EventHeader(EventId(2), 0, (trigger_id,)),
        ScheduledEvent(0, 0, ScheduledEventKind.LOCKDOWN),
    )

    assert build_glasshouse_sound_cues((started, lockdown)) == (
        GlasshouseSoundCue(2, GlasshouseSoundCueKind.LOCKDOWN),
    )


def test_glasshouse_sound_cues_reject_noncanonical_input() -> None:
    with pytest.raises(TypeError, match="immutable canonical events"):
        build_glasshouse_sound_cues([])  # type: ignore[arg-type]
