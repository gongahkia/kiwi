from __future__ import annotations

import pytest

from kiwi.domain.ids import EntityId
from kiwi.sim.commands import (
    CommandHeader,
    CommandSource,
    IssueSignal,
    RequestAbort,
    SignalName,
    StartMission,
    canonical_command_order,
)


def header(tick: int, sequence: int, source: CommandSource = CommandSource.PLAYER) -> CommandHeader:
    return CommandHeader(tick=tick, sequence=sequence, source=source)


def test_commands_have_typed_headers_and_canonical_tick_sequence_order() -> None:
    abort = RequestAbort(header(5, 9))
    start = StartMission(header(0, 3, CommandSource.SCENARIO))
    signal = IssueSignal(header(5, 4), SignalName("hold"), target=EntityId(2))

    assert canonical_command_order((abort, signal, start)) == (start, signal, abort)


def test_canonical_command_order_is_independent_of_input_order() -> None:
    first = IssueSignal(header(2, 1), SignalName("advance"))
    second = RequestAbort(header(1, 2))
    expected = (second, first)

    assert canonical_command_order((first, second)) == expected
    assert canonical_command_order((second, first)) == expected


@pytest.mark.parametrize(
    ("factory", "message"),
    (
        (lambda: CommandHeader(-1, 0, CommandSource.PLAYER), "non-negative"),
        (lambda: CommandHeader(0, -1, CommandSource.PLAYER), "non-negative"),
        (lambda: CommandHeader(0, 0, "player"), "CommandSource"),  # type: ignore[arg-type]
        (lambda: SignalName("Hold"), "lowercase"),
        (lambda: IssueSignal(header(0, 0), SignalName("hold"), target=object()), "entity ID"),  # type: ignore[arg-type]
        (
            lambda: canonical_command_order(
                (StartMission(header(0, 1)), RequestAbort(header(2, 1)))
            ),
            "globally unique",
        ),
        (lambda: canonical_command_order((object(),)), "external commands"),  # type: ignore[arg-type]
    ),
)
def test_commands_reject_invalid_values_and_ambiguous_order(factory: object, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        factory()  # type: ignore[operator]
