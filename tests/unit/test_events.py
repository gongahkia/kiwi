from __future__ import annotations

import pytest

from kiwi.domain.ids import EntityId, EventId
from kiwi.sim.commands import CommandHeader, CommandSource, IssueSignal, SignalName, StartMission
from kiwi.sim.events import (
    EventHeader,
    EventKind,
    MissionStarted,
    RandomDrawRecorded,
    SignalIssued,
    canonical_event_order,
    event_kind,
)
from kiwi.sim.randomness import (
    MissionSeed,
    RandomPurpose,
    RandomStreamId,
    RandomStreams,
    draw_uint32,
)


def test_event_algebra_preserves_sources_and_canonical_order() -> None:
    start_command = StartMission(CommandHeader(0, 0, CommandSource.SCENARIO))
    signal_command = IssueSignal(
        CommandHeader(3, 1, CommandSource.PLAYER),
        SignalName("hold"),
        EntityId(2),
    )
    started = MissionStarted(EventHeader(EventId(2), 0), start_command)
    signalled = SignalIssued(EventHeader(EventId(3), 3, (EventId(2),)), signal_command)

    assert canonical_event_order((signalled, started)) == (started, signalled)
    assert event_kind(started) is EventKind.MISSION_STARTED
    assert event_kind(signalled) is EventKind.SIGNAL_ISSUED


def test_random_draw_events_retain_the_full_record() -> None:
    _, draw, _ = draw_uint32(
        RandomStreams.from_seed(MissionSeed(1)),
        RandomStreamId.DAMAGE_VARIATION,
        RandomPurpose("damage_variation"),
    )
    event = RandomDrawRecorded(EventHeader(EventId(3), 1), draw)

    assert event.draw == draw
    assert event_kind(event) is EventKind.RANDOM_DRAW_RECORDED


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: EventHeader(EventId(1), 0, [EventId(2)]), "immutable tuple"),  # type: ignore[arg-type]
        (lambda: EventHeader(EventId(4), 0, (EventId(3), EventId(2))), "ascending"),
        (lambda: EventHeader(EventId(2), 0, (EventId(3),)), "precede the event ID"),
        (
            lambda: MissionStarted(
                EventHeader(EventId(1), 1),
                StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),
            ),
            "match its source tick",
        ),
        (
            lambda: canonical_event_order(
                (
                    MissionStarted(
                        EventHeader(EventId(1), 0),
                        StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),
                    ),
                    MissionStarted(
                        EventHeader(EventId(1), 1),
                        StartMission(CommandHeader(1, 1, CommandSource.SCENARIO)),
                    ),
                )
            ),
            "globally unique",
        ),
        (lambda: canonical_event_order((object(),)), "canonical events"),  # type: ignore[arg-type]
    ),
)
def test_events_reject_invalid_headers_sources_and_order(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
