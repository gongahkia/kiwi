"""Pure headless execution over an exact number of authoritative ticks."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.sim.clock import FixedTickClock
from kiwi.sim.commands import ExternalCommand, canonical_command_order
from kiwi.sim.events import CanonicalEvent, canonical_event_order
from kiwi.sim.limits import MAX_AUTHORITY_TICK
from kiwi.sim.policies import EMPTY_POLICY_BINDINGS, PolicyBindings
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.snapshot import AuthoritySnapshot, capture_authority_snapshot
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class HeadlessRun:
    """The final authority state and complete canonical event stream of one run."""

    state: MissionState
    events: tuple[CanonicalEvent, ...]
    checkpoints: tuple[AuthoritySnapshot, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise ValueError("headless run requires mission state")
        if not isinstance(self.events, tuple):
            raise ValueError("headless run events must be an immutable tuple")
        if canonical_event_order(self.events) != self.events:
            raise ValueError("headless run events must be canonically ordered")
        if not isinstance(self.checkpoints, tuple):
            raise ValueError("headless run checkpoints must be an immutable tuple")
        previous_tick = -1
        for checkpoint in self.checkpoints:
            if not isinstance(checkpoint, AuthoritySnapshot):
                raise ValueError("headless run checkpoints must be authority snapshots")
            if checkpoint.tick <= previous_tick or checkpoint.tick > self.state.tick:
                raise ValueError("headless run checkpoints must be ascending run ticks")
            previous_tick = checkpoint.tick


def run_headless(
    state: MissionState,
    clock: FixedTickClock,
    ticks: int,
    commands: tuple[ExternalCommand, ...] = (),
    checkpoint_interval: int | None = None,
    policy_bindings: PolicyBindings = EMPTY_POLICY_BINDINGS,
) -> HeadlessRun:
    """Advance exactly `ticks` authority steps without frames or presentation state."""
    if not isinstance(state, MissionState):
        raise ValueError("headless run requires mission state")
    if not isinstance(clock, FixedTickClock):
        raise ValueError("headless run requires a fixed tick clock")
    if not isinstance(ticks, int) or isinstance(ticks, bool):
        raise ValueError("headless run tick count must be an integer")
    if ticks < 0:
        raise ValueError("headless run tick count must be non-negative")
    if state.tick + ticks > MAX_AUTHORITY_TICK:
        raise ValueError("headless run would exceed the mission tick limit")
    if not isinstance(commands, tuple):
        raise ValueError("headless run commands must be an immutable tuple")
    if not isinstance(policy_bindings, PolicyBindings):
        raise ValueError("headless run policy bindings must be policy bindings")
    if checkpoint_interval is not None and (
        not isinstance(checkpoint_interval, int)
        or isinstance(checkpoint_interval, bool)
        or checkpoint_interval <= 0
    ):
        raise ValueError("headless run checkpoint interval must be a positive integer or None")

    ordered_commands = canonical_command_order(commands)
    end_tick = state.tick + ticks
    for command in ordered_commands:
        if not state.tick <= command.header.tick < end_tick:
            raise ValueError("headless run commands must target an executed tick")

    current_state = state
    command_index = 0
    events: list[CanonicalEvent] = []
    checkpoints = (
        [capture_authority_snapshot(current_state)] if checkpoint_interval is not None else []
    )
    while current_state.tick < end_tick:
        current_commands: list[ExternalCommand] = []
        while (
            command_index < len(ordered_commands)
            and ordered_commands[command_index].header.tick == current_state.tick
        ):
            current_commands.append(ordered_commands[command_index])
            command_index += 1
        result = reduce_one_tick(
            current_state,
            clock,
            tuple(current_commands),
            policy_bindings,
        )
        current_state = result.state
        events.extend(result.events)
        if checkpoint_interval is not None and (
            (current_state.tick - state.tick) % checkpoint_interval == 0
            or current_state.tick == end_tick
        ):
            checkpoints.append(capture_authority_snapshot(current_state))
    return HeadlessRun(current_state, canonical_event_order(events), tuple(checkpoints))
