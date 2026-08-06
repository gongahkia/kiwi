"""Deterministic Glasshouse deployment, tick execution, and signal queueing."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum

from kiwi.app.glasshouse_hostiles import (
    GlasshouseHostileSetup,
    build_glasshouse_hostile_setup,
)
from kiwi.app.glasshouse_players import (
    GlasshousePlayerSetup,
    GlasshousePolicyFailure,
    build_glasshouse_player_setup,
)
from kiwi.content.missions import MissionData
from kiwi.domain.ids import MAX_STABLE_ID, EntityId
from kiwi.dsl.source import SourceFile
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import (
    CommandHeader,
    CommandSource,
    ExternalCommand,
    IssueSignal,
    SignalName,
    StartMission,
    canonical_command_order,
)
from kiwi.sim.events import CanonicalEvent, SignalIssued, canonical_event_order
from kiwi.sim.policies import PolicyBindings
from kiwi.sim.reducer import reduce_one_tick
from kiwi.sim.scheduled import ScheduledEventKind
from kiwi.sim.snapshot import build_presentation_snapshot
from kiwi.sim.state import MissionPhase, MissionState
from kiwi.ui.glasshouse_mission import (
    GlasshouseMissionPresentation,
    GlasshouseSignalStatus,
    build_glasshouse_mission_summary,
)
from kiwi.ui.glasshouse_workbench import GlasshouseFlowPhase, GlasshouseWorkbench


class GlasshouseSignal(StrEnum):
    """The limited strategic signal vocabulary offered during Glasshouse."""

    ADVANCE = "advance"
    HOLD = "hold"


@dataclass(frozen=True, slots=True)
class GlasshouseMissionExecution:
    """Application-owned execution state around immutable authoritative ticks."""

    state: MissionState
    initial_state: MissionState
    clock: FixedTickClock
    policy_bindings: PolicyBindings
    policy_sources: tuple[SourceFile, ...]
    player_entity_ids: tuple[EntityId, ...]
    lockdown_tick: int
    next_command_sequence: int = 0
    queued_commands: tuple[ExternalCommand, ...] = ()
    command_log: tuple[ExternalCommand, ...] = ()
    events: tuple[CanonicalEvent, ...] = ()
    last_tick_events: tuple[CanonicalEvent, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.state, MissionState):
            raise TypeError("Glasshouse execution requires mission state")
        if not isinstance(self.initial_state, MissionState):
            raise TypeError("Glasshouse execution requires initial mission state")
        if self.initial_state.tick > self.state.tick:
            raise ValueError("Glasshouse initial mission state must not follow current state")
        if not isinstance(self.clock, FixedTickClock):
            raise TypeError("Glasshouse execution requires a fixed tick clock")
        if not isinstance(self.policy_bindings, PolicyBindings):
            raise TypeError("Glasshouse execution requires policy bindings")
        _validate_policy_sources(self.policy_sources, self.policy_bindings)
        if not isinstance(self.player_entity_ids, tuple) or len(self.player_entity_ids) != 4:
            raise ValueError("Glasshouse execution requires four player entity IDs")
        if any(not isinstance(entity_id, EntityId) for entity_id in self.player_entity_ids):
            raise TypeError("Glasshouse player entity IDs are invalid")
        if self.player_entity_ids != tuple(
            sorted(self.player_entity_ids, key=lambda item: item.value)
        ):
            raise ValueError("Glasshouse player entity IDs must be ordered")
        state_entity_ids = tuple(entity.entity_id for entity in self.state.entities)
        if any(entity_id not in state_entity_ids for entity_id in self.player_entity_ids):
            raise ValueError("Glasshouse player entity IDs must belong to mission state")
        if (
            not isinstance(self.lockdown_tick, int)
            or isinstance(self.lockdown_tick, bool)
            or self.lockdown_tick < 0
        ):
            raise ValueError("Glasshouse lockdown tick is invalid")
        if (
            not isinstance(self.next_command_sequence, int)
            or isinstance(self.next_command_sequence, bool)
            or not 0 <= self.next_command_sequence <= MAX_STABLE_ID + 1
        ):
            raise ValueError("Glasshouse command sequence is invalid")
        if not isinstance(self.queued_commands, tuple):
            raise TypeError("Glasshouse queued commands must be immutable")
        ordered_commands = canonical_command_order(self.queued_commands)
        if ordered_commands != self.queued_commands:
            raise ValueError("Glasshouse queued commands must be canonical")
        if any(command.header.tick != self.state.tick for command in self.queued_commands):
            raise ValueError("Glasshouse queued commands must target the current tick")
        if any(
            command.header.sequence >= self.next_command_sequence
            for command in self.queued_commands
        ):
            raise ValueError("Glasshouse queued command sequence is invalid")
        if canonical_command_order(self.command_log) != self.command_log:
            raise ValueError("Glasshouse command log must be canonical")
        if any(
            not self.initial_state.tick <= command.header.tick < self.state.tick
            for command in self.command_log
        ):
            raise ValueError("Glasshouse command log must target resolved ticks")
        if any(
            command.header.sequence >= self.next_command_sequence for command in self.command_log
        ):
            raise ValueError("Glasshouse command log sequence is invalid")
        if not isinstance(self.events, tuple) or canonical_event_order(self.events) != self.events:
            raise ValueError("Glasshouse execution events must be canonical")
        if (
            not isinstance(self.last_tick_events, tuple)
            or canonical_event_order(self.last_tick_events) != self.last_tick_events
        ):
            raise ValueError("Glasshouse execution tick events must be canonical")
        if self.last_tick_events and (
            self.state.tick == 0
            or any(event.header.tick != self.state.tick - 1 for event in self.last_tick_events)
        ):
            raise ValueError("Glasshouse execution tick events must precede current state")

    @property
    def remaining_lockdown_ticks(self) -> int:
        """Return the exact non-negative time before Glasshouse lockdown."""
        return max(0, self.lockdown_tick - self.state.tick)

    @property
    def last_signal(self) -> SignalIssued | None:
        """Return the latest recorded high-level signal, if one has been issued."""
        for event in reversed(self.events):
            if isinstance(event, SignalIssued):
                return event
        return None

    def request_start(self) -> GlasshouseMissionExecution:
        """Queue the player's start request for the next authoritative tick."""
        if self.state.phase is not MissionPhase.PREPARED:
            raise ValueError("Glasshouse mission is not prepared")
        if self.queued_commands:
            raise ValueError("Glasshouse mission start is already queued")
        return self._queue(StartMission(self._next_header()))

    def queue_signal(
        self, signal: GlasshouseSignal, target: EntityId | None = None
    ) -> GlasshouseMissionExecution:
        """Queue one permitted strategic signal without direct operative control."""
        if self.state.phase is not MissionPhase.ACTIVE:
            raise ValueError("Glasshouse mission must be active before issuing a signal")
        if not isinstance(signal, GlasshouseSignal):
            raise TypeError("Glasshouse signal is invalid")
        if target is not None and not isinstance(target, EntityId):
            raise TypeError("Glasshouse signal target must be an entity ID or absent")
        if target is not None and target not in self.player_entity_ids:
            raise ValueError("Glasshouse signals may target only deployed player operatives")
        return self._queue(IssueSignal(self._next_header(), SignalName(signal.value), target))

    def advance(self) -> GlasshouseMissionExecution:
        """Resolve exactly one authority tick and retain its canonical events."""
        result = reduce_one_tick(
            self.state,
            self.clock,
            self.queued_commands,
            self.policy_bindings,
        )
        return replace(
            self,
            state=result.state,
            queued_commands=(),
            command_log=canonical_command_order((*self.command_log, *self.queued_commands)),
            events=canonical_event_order((*self.events, *result.events)),
            last_tick_events=result.events,
        )

    def _next_header(self) -> CommandHeader:
        if self.next_command_sequence > MAX_STABLE_ID:
            raise ValueError("Glasshouse command sequence is exhausted")
        return CommandHeader(self.state.tick, self.next_command_sequence, CommandSource.PLAYER)

    def _queue(self, command: ExternalCommand) -> GlasshouseMissionExecution:
        return replace(
            self,
            queued_commands=canonical_command_order((*self.queued_commands, command)),
            next_command_sequence=self.next_command_sequence + 1,
        )


type GlasshouseMissionExecutionResult = GlasshouseMissionExecution | GlasshousePolicyFailure


def build_glasshouse_mission_execution(
    mission: MissionData,
    workbench: GlasshouseWorkbench,
    hostile_sources: tuple[SourceFile, ...],
) -> GlasshouseMissionExecutionResult:
    """Compile the current workbench bundle and prepare one headless Glasshouse run."""
    if not isinstance(mission, MissionData):
        raise TypeError("Glasshouse execution requires mission data")
    if mission.mission_id != "glasshouse":
        raise ValueError("Glasshouse execution requires the Glasshouse mission")
    if not isinstance(workbench, GlasshouseWorkbench):
        raise TypeError("Glasshouse execution requires a workbench")
    if workbench.phase is not GlasshouseFlowPhase.WORKBENCH:
        raise ValueError("Glasshouse workbench must be open before deployment")
    players = build_glasshouse_player_setup(mission, workbench.sources)
    if isinstance(players, GlasshousePolicyFailure):
        return players
    hostiles = build_glasshouse_hostile_setup(players, hostile_sources)
    if isinstance(hostiles, GlasshousePolicyFailure):
        return hostiles
    return _execution_from_setups(mission, players, hostiles, workbench.sources, hostile_sources)


def build_glasshouse_mission_presentation(
    execution: GlasshouseMissionExecution,
) -> GlasshouseMissionPresentation:
    """Copy one execution state into a renderer-safe mission HUD input."""
    if not isinstance(execution, GlasshouseMissionExecution):
        raise TypeError("Glasshouse mission presentation requires execution state")
    queued_signals = tuple(
        command for command in execution.queued_commands if isinstance(command, IssueSignal)
    )
    if queued_signals:
        command = queued_signals[-1]
        signal_status = GlasshouseSignalStatus(
            command.signal.value,
            None if command.target is None else command.target.value,
            True,
        )
    elif execution.last_signal is not None:
        command = execution.last_signal.command
        signal_status = GlasshouseSignalStatus(
            command.signal.value,
            None if command.target is None else command.target.value,
            False,
        )
    else:
        signal_status = None
    objectives = execution.state.objectives.entries
    if len(objectives) != 1:
        raise AssertionError("Glasshouse mission presentation requires one objective")
    return GlasshouseMissionPresentation(
        build_presentation_snapshot(execution.state, projectile_events=execution.last_tick_events),
        build_glasshouse_mission_summary(
            objectives[0].status,
            lockdown_active=execution.state.lockdown.active,
        ),
        execution.remaining_lockdown_ticks,
        signal_status,
    )


def _execution_from_setups(
    mission: MissionData,
    players: GlasshousePlayerSetup,
    hostiles: GlasshouseHostileSetup,
    player_sources: tuple[SourceFile, ...],
    hostile_sources: tuple[SourceFile, ...],
) -> GlasshouseMissionExecution:
    lockdown_events = tuple(
        event
        for event in hostiles.state.scheduled_events.pending
        if event.kind is ScheduledEventKind.LOCKDOWN
    )
    if len(lockdown_events) != 1:
        raise AssertionError("Glasshouse mission requires exactly one lockdown event")
    return GlasshouseMissionExecution(
        state=hostiles.state,
        initial_state=hostiles.state,
        clock=FixedTickClock(TickRate(mission.tick_rate)),
        policy_bindings=hostiles.policy_bindings,
        policy_sources=tuple(
            sorted((*player_sources, *hostile_sources), key=lambda source: source.file_id)
        ),
        player_entity_ids=tuple(player.entity_id for player in players.players),
        lockdown_tick=lockdown_events[0].tick,
    )


def _validate_policy_sources(sources: tuple[SourceFile, ...], bindings: PolicyBindings) -> None:
    if not isinstance(sources, tuple) or any(
        not isinstance(source, SourceFile) for source in sources
    ):
        raise TypeError("Glasshouse policy sources must be immutable source files")
    source_file_ids = tuple(source.file_id for source in sources)
    if source_file_ids != tuple(sorted(source_file_ids)) or len(set(source_file_ids)) != len(
        source_file_ids
    ):
        raise ValueError("Glasshouse policy sources must be unique and source-file ordered")
    binding_file_ids = tuple(
        sorted(
            (binding.artifact.bytecode.header.source_file_id for binding in bindings.entries),
        )
    )
    if source_file_ids != binding_file_ids:
        raise ValueError("Glasshouse policy sources must match deployed policy bindings")
