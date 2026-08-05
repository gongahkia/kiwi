"""Headless construction of immutable replay manifests."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.replay.format import ReplayCheckpoint, ReplayPacket
from kiwi.sim.clock import FixedTickClock
from kiwi.sim.commands import ExternalCommand, canonical_command_order
from kiwi.sim.policies import EMPTY_POLICY_BINDINGS, PolicyBindings
from kiwi.sim.policy_versions import EntityPolicyVersion
from kiwi.sim.runner import HeadlessRun, run_headless
from kiwi.sim.snapshot import capture_authority_snapshot
from kiwi.sim.state import MissionState


@dataclass(frozen=True, slots=True)
class RecordedReplay:
    """One replay packet paired with the exact headless run that produced it."""

    replay: ReplayPacket
    run: HeadlessRun

    def __post_init__(self) -> None:
        if not isinstance(self.replay, ReplayPacket):
            raise ValueError("recorded replay requires a ReplayPacket")
        if not isinstance(self.run, HeadlessRun):
            raise ValueError("recorded replay requires a HeadlessRun")
        expected_checkpoints = tuple(
            ReplayCheckpoint(checkpoint.tick, checkpoint.state_hash)
            for checkpoint in self.run.checkpoints
        )
        if not self.run.checkpoints or self.replay.initial_snapshot != self.run.checkpoints[0]:
            raise ValueError("recorded replay initial snapshot must match the headless run")
        if self.replay.checkpoints != expected_checkpoints:
            raise ValueError("recorded replay checkpoints must match the headless run")


def record_headless_run(
    initial_state: MissionState,
    clock: FixedTickClock,
    ticks: int,
    *,
    application_build: str,
    simulation_version: str,
    mission_hash: bytes,
    commands: tuple[ExternalCommand, ...] = (),
    checkpoint_interval: int = 1,
    policy_bindings: PolicyBindings = EMPTY_POLICY_BINDINGS,
) -> RecordedReplay:
    """Run headlessly and retain every v1 replay input plus canonical checkpoints."""
    if not isinstance(initial_state, MissionState):
        raise TypeError("replay recording requires mission state")
    if not isinstance(clock, FixedTickClock):
        raise TypeError("replay recording requires a fixed tick clock")
    if not isinstance(commands, tuple):
        raise ValueError("replay recording commands must be an immutable tuple")
    if not isinstance(policy_bindings, PolicyBindings):
        raise TypeError("replay recording requires policy bindings")
    if (
        not isinstance(checkpoint_interval, int)
        or isinstance(checkpoint_interval, bool)
        or checkpoint_interval <= 0
    ):
        raise ValueError("replay recording checkpoint interval must be a positive integer")
    _require_bound_entities(initial_state, policy_bindings)
    initial_snapshot = capture_authority_snapshot(initial_state)
    ordered_commands = canonical_command_order(commands)
    run = run_headless(
        initial_state,
        clock,
        ticks,
        ordered_commands,
        checkpoint_interval,
        policy_bindings,
    )
    replay = ReplayPacket(
        application_build=application_build,
        simulation_version=simulation_version,
        mission_hash=mission_hash,
        policy_versions=tuple(
            EntityPolicyVersion(binding.entity_id, binding.policy_version)
            for binding in policy_bindings.entries
        ),
        initial_snapshot=initial_snapshot,
        seed=initial_state.random_streams.seed,
        tick_rate=clock.rate,
        commands=ordered_commands,
        checkpoints=tuple(
            ReplayCheckpoint(checkpoint.tick, checkpoint.state_hash)
            for checkpoint in run.checkpoints
        ),
    )
    return RecordedReplay(replay, run)


def _require_bound_entities(state: MissionState, bindings: PolicyBindings) -> None:
    entity_ids = tuple(entity.entity_id for entity in state.entities)
    if any(binding.entity_id not in entity_ids for binding in bindings.entries):
        raise ValueError("replay policy bindings must belong to initial mission entities")
