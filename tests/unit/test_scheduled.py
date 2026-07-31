from __future__ import annotations

import pytest

from kiwi.domain.ids import MAX_STABLE_ID
from kiwi.sim.scheduled import ScheduledEvent, ScheduledEventKind, ScheduledEventQueue


def test_scheduled_events_use_canonical_tick_sequence_order() -> None:
    initial = ScheduledEventQueue()
    later, after_later = initial.schedule(8, ScheduledEventKind.SCENARIO_TRIGGER)
    earlier, queue = after_later.schedule(3, ScheduledEventKind.SCENARIO_TRIGGER)

    assert initial == ScheduledEventQueue()
    assert later.sequence == 0
    assert earlier.sequence == 1
    assert queue.pending == (earlier, later)


def test_due_events_are_removed_only_at_the_exact_tick() -> None:
    first, after_first = ScheduledEventQueue().schedule(4, ScheduledEventKind.SCENARIO_TRIGGER)
    second, queue = after_first.schedule(4, ScheduledEventKind.SCENARIO_TRIGGER)

    absent, unchanged = queue.due_at(3)
    due, remaining = queue.due_at(4)

    assert absent == ()
    assert unchanged == queue
    assert due == (first, second)
    assert remaining.pending == ()
    assert remaining.next_sequence == 2


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (
            lambda: ScheduledEventQueue(
                pending=(
                    ScheduledEvent(2, 1, ScheduledEventKind.SCENARIO_TRIGGER),
                    ScheduledEvent(1, 0, ScheduledEventKind.SCENARIO_TRIGGER),
                ),
                next_sequence=2,
            ),
            "tick-sequence ordered",
        ),
        (
            lambda: ScheduledEventQueue(
                pending=(ScheduledEvent(1, 0, ScheduledEventKind.SCENARIO_TRIGGER),),
                next_sequence=0,
            ),
            "precede",
        ),
        (
            lambda: ScheduledEventQueue(
                pending=(
                    ScheduledEvent(1, 0, ScheduledEventKind.SCENARIO_TRIGGER),
                    ScheduledEvent(2, 0, ScheduledEventKind.SCENARIO_TRIGGER),
                ),
                next_sequence=1,
            ),
            "sequences must be unique",
        ),
        (lambda: ScheduledEventQueue(next_sequence=MAX_STABLE_ID + 2), "signed 64-bit"),
        (
            lambda: ScheduledEventQueue(next_sequence=MAX_STABLE_ID + 1).schedule(
                0, ScheduledEventKind.SCENARIO_TRIGGER
            ),
            "exhausted",
        ),
        (lambda: ScheduledEvent(0, 0, "scenario_trigger"), "ScheduledEventKind"),  # type: ignore[arg-type]
    ),
)
def test_scheduled_queue_rejects_noncanonical_values(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
