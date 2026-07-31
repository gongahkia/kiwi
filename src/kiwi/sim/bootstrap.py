"""Canonical construction of the current kernel state from validated inputs."""

from __future__ import annotations

from kiwi.domain.geometry import WorldPosition
from kiwi.sim.randomness import MissionSeed, RandomStreams
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.state import MissionState, add_entity


def build_initial_state(
    seed: MissionSeed,
    entity_positions: tuple[WorldPosition, ...],
    scheduled_trigger_ticks: tuple[int, ...],
) -> MissionState:
    """Build state from already canonicalised fixture primitives in supplied order."""
    if not isinstance(seed, MissionSeed):
        raise ValueError("initial mission seed must be a MissionSeed")
    if not isinstance(entity_positions, tuple):
        raise ValueError("initial entity positions must be an immutable tuple")
    if not isinstance(scheduled_trigger_ticks, tuple):
        raise ValueError("initial scheduled trigger ticks must be an immutable tuple")
    state = MissionState(random_streams=RandomStreams.from_seed(seed))
    for position in entity_positions:
        state, _ = add_entity(state, position)
    previous_tick = -1
    for tick in scheduled_trigger_ticks:
        if not isinstance(tick, int) or isinstance(tick, bool) or tick < previous_tick:
            raise ValueError("initial scheduled trigger ticks must be ascending integers")
        _, queue = state.scheduled_events.schedule(tick, ScheduledEventKind.SCENARIO_TRIGGER)
        state = MissionState(
            tick=state.tick,
            phase=state.phase,
            entities=state.entities,
            id_allocator=state.id_allocator,
            scheduled_events=queue,
            random_streams=state.random_streams,
        )
        previous_tick = tick
    return state
