"""Runnable, deterministic Glasshouse causal-drill application state."""

from __future__ import annotations

from dataclasses import dataclass, replace
from enum import StrEnum
from pathlib import Path
from platform import system

from kiwi.app.glasshouse_players import PLAYER_MEMORY_SCHEMA
from kiwi.app.glasshouse_workbench import build_glasshouse_workbench
from kiwi.domain.geometry import WorldPosition, WorldRectangle, WorldSubunits
from kiwi.domain.ids import TraceNodeId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import BooleanValue, RecordValue, StringValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId, SourceSpan
from kiwi.dsl.types import BuiltinType
from kiwi.replay.recording import RecordedReplay, record_headless_run
from kiwi.replay.source_archive import (
    HistoricalSourceFile,
    ReplaySourceArchive,
    build_source_archive,
)
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.conditions import OperativeCondition, OperativeConditionStore
from kiwi.sim.contacts import (
    ContactConfidence,
    ContactEstimate,
    ContactField,
    ContactFieldProvenance,
    ContactProvenance,
    ContactStore,
)
from kiwi.sim.covers import (
    CoverHeight,
    CoverIntegrity,
    CoverSegment,
    CoverSide,
    CoverSlot,
    CoverStore,
)
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.map_geometry import MapGeometry
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.snapshot import (
    PresentationSnapshot,
    SnapshotRestoreFailure,
    build_presentation_snapshot,
    restore_authority_snapshot,
)
from kiwi.sim.state import EntityState, MissionState, add_entity
from kiwi.sim.weapons import Ammunition, EquippedWeapon, WeaponStore
from kiwi.trace.capture import capture_run_trace
from kiwi.trace.model import (
    CausalTrace,
    ExpressionEvaluationTrace,
    IntentionTrace,
)
from kiwi.ui.dsl_completion import dsl_completion_suffix, dsl_completions
from kiwi.ui.editor import EditorState
from kiwi.ui.glasshouse_debrief import (
    GlasshouseDebrief,
    GlasshouseDebriefResult,
    GlasshouseDebriefUnavailable,
    glasshouse_debrief,
)
from kiwi.ui.glasshouse_revision import (
    GlasshouseGuidedRevision,
    GuidedRevisionResult,
    guided_source_revision,
)
from kiwi.ui.glasshouse_tutorial import GLASSHOUSE_LANGUAGE_TUTORIAL, GlasshouseTutorial
from kiwi.ui.glasshouse_workbench import GlasshouseFlowPhase, GlasshouseWorkbench
from kiwi.ui.run_comparison import RunComparisonView, run_comparison_view

_REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
_ENEMY_SOURCE_ID = "examples/policies/glasshouse/causal_drill_enemy.dtr"
_DEMO_APPLICATION_BUILD = "glasshouse-demo"
_DEMO_SIMULATION_VERSION = "sim-v1"
_DEMO_MISSION_HASH = b"glasshouse-causal-drill-demo-v1!"
_DEMO_TICKS = 2
_ENEMY_MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("fired", BuiltinType.BOOL),))


class GlasshouseDemoScreen(StrEnum):
    """The finite non-authoritative screens in the manual Glasshouse drill."""

    INPUT_SETUP = "input_setup"
    BRIEFING = "briefing"
    WORKBENCH = "workbench"
    LIVE_PREVIEW = "live_preview"
    GUIDE = "guide"
    MISSION = "mission"
    DEBRIEF = "debrief"
    COMPARISON = "comparison"


class GlasshouseInputMode(StrEnum):
    """The explicitly selected shortcut set for the local pygame shell."""

    STANDARD = "standard"
    FUNCTION_KEYS = "function_keys"


class GlasshouseColorScheme(StrEnum):
    """The selectable presentation-only terminal palettes."""

    CYAN = "cyan"
    AMBER = "amber"
    PHOSPHOR = "phosphor"


@dataclass(frozen=True, slots=True)
class GlasshouseDemoRun:
    """One recorded causal drill with its trace and historical source archive."""

    recorded: RecordedReplay
    trace: CausalTrace
    archive: ReplaySourceArchive
    snapshots: tuple[PresentationSnapshot, ...]
    debrief: GlasshouseDebriefResult

    def __post_init__(self) -> None:
        if not isinstance(self.recorded, RecordedReplay):
            raise TypeError("Glasshouse demo run requires a recorded replay")
        if not isinstance(self.trace, CausalTrace):
            raise TypeError("Glasshouse demo run requires a causal trace")
        if not isinstance(self.archive, ReplaySourceArchive):
            raise TypeError("Glasshouse demo run requires a source archive")
        if not isinstance(self.snapshots, tuple) or not self.snapshots:
            raise ValueError("Glasshouse demo run requires presentation snapshots")
        if any(not isinstance(snapshot, PresentationSnapshot) for snapshot in self.snapshots):
            raise TypeError("Glasshouse demo snapshots must be presentation snapshots")
        if not isinstance(self.debrief, (GlasshouseDebrief, GlasshouseDebriefUnavailable)):
            raise TypeError("Glasshouse demo run requires a debrief result")
        if self.trace.run_state_hash != hash_canonical_state(self.recorded.run.state).digest:
            raise ValueError("Glasshouse demo trace must match the recorded run")
        checkpoint_ticks = tuple(checkpoint.tick for checkpoint in self.recorded.run.checkpoints)
        if tuple(snapshot.tick for snapshot in self.snapshots) != checkpoint_ticks:
            raise ValueError("Glasshouse demo snapshots must match recorded checkpoint ticks")


@dataclass(frozen=True, slots=True)
class GlasshouseDemoDeploymentFailure:
    """A deployment attempt stopped by compile diagnostics already held by the workbench."""

    workbench: GlasshouseWorkbench

    def __post_init__(self) -> None:
        if not isinstance(self.workbench, GlasshouseWorkbench):
            raise TypeError("Glasshouse demo deployment failure requires a workbench")
        if self.workbench.phase is not GlasshouseFlowPhase.WORKBENCH:
            raise ValueError("Glasshouse demo deployment failure requires an open workbench")
        if all(
            output is not None and output.succeeded for output in self.workbench.compile_outputs
        ):
            raise ValueError("Glasshouse demo deployment failure requires a failed compile output")


type GlasshouseDemoDeploymentResult = GlasshouseDemoRun | GlasshouseDemoDeploymentFailure


@dataclass(frozen=True, slots=True)
class GlasshouseDemoController:
    """Pure screen and source-edit flow consumed by the pygame Glasshouse shell."""

    screen: GlasshouseDemoScreen
    workbench: GlasshouseWorkbench
    input_mode: GlasshouseInputMode
    detected_platform: str
    tutorial: GlasshouseTutorial = GLASSHOUSE_LANGUAGE_TUTORIAL
    current_run: GlasshouseDemoRun | None = None
    baseline_run: GlasshouseDemoRun | None = None
    comparison: RunComparisonView | None = None
    preview_snapshot_index: int = 0
    preview_playing: bool = False
    preview_stale: bool = False
    hot_reload_enabled: bool = True
    preview_rotation_quarters: int = 0
    selected_trace_node_id: TraceNodeId | None = None
    preview_selected_entity_id: int | None = None
    color_scheme: GlasshouseColorScheme = GlasshouseColorScheme.CYAN
    notice: str = ""

    def __post_init__(self) -> None:
        if not isinstance(self.screen, GlasshouseDemoScreen):
            raise TypeError("Glasshouse demo screen is invalid")
        if not isinstance(self.workbench, GlasshouseWorkbench):
            raise TypeError("Glasshouse demo workbench is invalid")
        if not isinstance(self.input_mode, GlasshouseInputMode):
            raise TypeError("Glasshouse demo input mode is invalid")
        if not isinstance(self.detected_platform, str) or not self.detected_platform:
            raise ValueError("Glasshouse demo detected platform must be text")
        if not isinstance(self.tutorial, GlasshouseTutorial):
            raise TypeError("Glasshouse demo tutorial is invalid")
        if self.current_run is not None and not isinstance(self.current_run, GlasshouseDemoRun):
            raise TypeError("Glasshouse demo current run is invalid")
        if self.baseline_run is not None and not isinstance(self.baseline_run, GlasshouseDemoRun):
            raise TypeError("Glasshouse demo baseline run is invalid")
        if self.comparison is not None and not isinstance(self.comparison, RunComparisonView):
            raise TypeError("Glasshouse demo comparison is invalid")
        if (
            not isinstance(self.preview_snapshot_index, int)
            or isinstance(self.preview_snapshot_index, bool)
            or self.preview_snapshot_index < 0
        ):
            raise ValueError("Glasshouse demo preview snapshot index is invalid")
        if not isinstance(self.preview_playing, bool):
            raise TypeError("Glasshouse demo preview playback flag is invalid")
        if not isinstance(self.preview_stale, bool):
            raise TypeError("Glasshouse demo preview stale flag is invalid")
        if not isinstance(self.hot_reload_enabled, bool):
            raise TypeError("Glasshouse demo hot reload flag is invalid")
        if (
            not isinstance(self.preview_rotation_quarters, int)
            or isinstance(self.preview_rotation_quarters, bool)
            or not 0 <= self.preview_rotation_quarters <= 3
        ):
            raise ValueError("Glasshouse demo preview rotation is invalid")
        if not isinstance(self.color_scheme, GlasshouseColorScheme):
            raise TypeError("Glasshouse demo color scheme is invalid")
        if self.selected_trace_node_id is not None and not isinstance(
            self.selected_trace_node_id, TraceNodeId
        ):
            raise TypeError("Glasshouse demo selected trace node is invalid")
        if self.preview_selected_entity_id is not None and (
            not isinstance(self.preview_selected_entity_id, int)
            or isinstance(self.preview_selected_entity_id, bool)
            or self.preview_selected_entity_id <= 0
        ):
            raise ValueError("Glasshouse demo selected entity is invalid")
        if not isinstance(self.notice, str):
            raise TypeError("Glasshouse demo notice must be text")
        if self.screen in (GlasshouseDemoScreen.INPUT_SETUP, GlasshouseDemoScreen.BRIEFING):
            if self.workbench.phase is not GlasshouseFlowPhase.BRIEFING:
                raise ValueError(
                    "Glasshouse demo pre-workbench screens require a briefing workbench"
                )
        elif self.workbench.phase is not GlasshouseFlowPhase.WORKBENCH:
            raise ValueError("Glasshouse demo screens after briefing require an open workbench")
        if (
            self.screen
            in (
                GlasshouseDemoScreen.MISSION,
                GlasshouseDemoScreen.DEBRIEF,
                GlasshouseDemoScreen.COMPARISON,
            )
            and self.current_run is None
        ):
            raise ValueError("Glasshouse demo run screens require a current run")
        if self.screen is GlasshouseDemoScreen.COMPARISON and self.comparison is None:
            raise ValueError("Glasshouse demo comparison screen requires a comparison")
        if self.screen is GlasshouseDemoScreen.LIVE_PREVIEW:
            if self.current_run is not None and self.preview_snapshot_index >= len(
                self.current_run.snapshots
            ):
                raise ValueError("Glasshouse demo preview snapshot index exceeds current run")
            if self.current_run is None and self.preview_stale:
                raise ValueError("Glasshouse demo missing preview cannot be stale")
        elif self.preview_playing:
            raise ValueError("Glasshouse demo playback is only valid in live preview")

    @classmethod
    def create(
        cls,
        repository_root: Path = _REPOSITORY_ROOT,
        platform_name: str | None = None,
    ) -> GlasshouseDemoController:
        """Load the shipped policies into platform-aware input setup."""
        resolved_platform = system() if platform_name is None else platform_name
        if not isinstance(resolved_platform, str):
            raise TypeError("Glasshouse demo platform name must be text")
        input_mode = (
            GlasshouseInputMode.STANDARD
            if resolved_platform == "Darwin"
            else GlasshouseInputMode.FUNCTION_KEYS
        )
        return cls(
            GlasshouseDemoScreen.INPUT_SETUP,
            load_glasshouse_workbench(repository_root),
            input_mode,
            resolved_platform,
        )

    def choose_input_mode(self, input_mode: GlasshouseInputMode) -> GlasshouseDemoController:
        """Choose the local shortcut set before the briefing begins."""
        if self.screen is not GlasshouseDemoScreen.INPUT_SETUP:
            return self
        if not isinstance(input_mode, GlasshouseInputMode):
            raise TypeError("Glasshouse demo input mode is invalid")
        return replace(self, input_mode=input_mode)

    def confirm_input_mode(self) -> GlasshouseDemoController:
        """Advance from local shortcut selection to the fixed mission briefing."""
        if self.screen is not GlasshouseDemoScreen.INPUT_SETUP:
            return self
        return replace(self, screen=GlasshouseDemoScreen.BRIEFING, notice="")

    def open_workbench(self) -> GlasshouseDemoController:
        """Advance from briefing to source review without starting authority."""
        if self.screen is not GlasshouseDemoScreen.BRIEFING:
            return self
        return replace(
            self,
            screen=GlasshouseDemoScreen.WORKBENCH,
            workbench=self.workbench.open_workbench(),
            notice="Review Lark's scout policy, then deploy the causal drill.",
        )

    def select_policy_index(self, index: int) -> GlasshouseDemoController:
        """Select one sidebar policy by its canonical workbench index."""
        if self.screen not in (GlasshouseDemoScreen.WORKBENCH, GlasshouseDemoScreen.LIVE_PREVIEW):
            return self
        if not isinstance(index, int) or isinstance(index, bool):
            raise TypeError("Glasshouse demo policy index must be an integer")
        if not 0 <= index < len(self.workbench.policies):
            raise ValueError("Glasshouse demo policy index is unavailable")
        return replace(
            self,
            workbench=self.workbench.select_policy(self.workbench.policies[index].role),
            notice="",
        )

    def cycle_color_scheme(self) -> GlasshouseDemoController:
        """Cycle the local terminal palette without changing source or authority."""
        schemes = tuple(GlasshouseColorScheme)
        index = (schemes.index(self.color_scheme) + 1) % len(schemes)
        scheme = schemes[index]
        return replace(self, color_scheme=scheme, notice=f"Theme: {scheme.value}.")

    def replace_selected_editor(self, editor: EditorState) -> GlasshouseDemoController:
        """Apply one already-validated non-authoritative editor operation."""
        if self.screen not in (GlasshouseDemoScreen.WORKBENCH, GlasshouseDemoScreen.LIVE_PREVIEW):
            return self
        source_changed = editor.buffer.text != self.workbench.editor.buffer.text
        updated = replace(self, workbench=self.workbench.replace_editor(editor), notice="")
        if (
            source_changed
            and updated.screen is GlasshouseDemoScreen.LIVE_PREVIEW
            and updated.hot_reload_enabled
        ):
            return updated.reload_preview()
        if source_changed and updated.screen is GlasshouseDemoScreen.LIVE_PREVIEW:
            return replace(
                updated,
                preview_stale=True,
                notice="Preview out of date: Compile + run to refresh.",
            )
        return updated

    def completions(self) -> tuple[str, ...]:
        """Return deterministic DSL completions for the selected source cursor."""
        if self.screen not in (GlasshouseDemoScreen.WORKBENCH, GlasshouseDemoScreen.LIVE_PREVIEW):
            return ()
        return dsl_completions(self.workbench.source.text, self.workbench.editor.cursor_offset)

    def accept_completion(self) -> GlasshouseDemoController:
        """Insert the first displayed DSL completion without interpreting player source."""
        options = self.completions()
        if not options:
            return self
        editor = self.workbench.editor
        suffix = dsl_completion_suffix(editor.buffer.text, editor.cursor_offset, options[0])
        return self if not suffix else self.replace_selected_editor(editor.insert_text(suffix))

    def compile_selected(self) -> GlasshouseDemoController:
        """Compile the selected closed-DSL policy without deployment."""
        if self.screen not in (GlasshouseDemoScreen.WORKBENCH, GlasshouseDemoScreen.LIVE_PREVIEW):
            return self
        compiled = self.workbench.compile_selected()
        notice = (
            "Compile succeeded."
            if compiled.compile_output and compiled.compile_output.succeeded
            else "Compile failed."
        )
        return replace(self, workbench=compiled, notice=notice)

    def select_scout_threshold(self) -> GlasshouseDemoController:
        """Select the shipped scout's caution literal without changing its source."""
        if self.screen not in (GlasshouseDemoScreen.WORKBENCH, GlasshouseDemoScreen.LIVE_PREVIEW):
            return self
        scout = self.workbench.select_policy("scout")
        span = _scout_caution_span(scout.source)
        if span is None:
            return replace(
                self, workbench=scout, notice="The shipped 1m caution literal is no longer present."
            )
        focused = replace(self, workbench=scout.focus_source(span))
        return replace(
            focused,
            notice="Caution numeral selected. Type 0 to hot reload the controlled rerun.",
        )

    def open_guide(self) -> GlasshouseDemoController:
        """Open the read-only language guide without changing source or authority."""
        if self.screen is not GlasshouseDemoScreen.WORKBENCH:
            return self
        return replace(self, screen=GlasshouseDemoScreen.GUIDE, notice="")

    def close_guide(self) -> GlasshouseDemoController:
        """Return from the guide to the unchanged workbench."""
        if self.screen is not GlasshouseDemoScreen.GUIDE:
            return self
        return replace(self, screen=GlasshouseDemoScreen.WORKBENCH, notice="")

    def next_lesson(self) -> GlasshouseDemoController:
        """Advance the read-only lesson selection when the guide is open."""
        if self.screen is not GlasshouseDemoScreen.GUIDE:
            return self
        return replace(self, tutorial=self.tutorial.next_lesson())

    def previous_lesson(self) -> GlasshouseDemoController:
        """Return to the preceding read-only lesson when the guide is open."""
        if self.screen is not GlasshouseDemoScreen.GUIDE:
            return self
        return replace(self, tutorial=self.tutorial.previous_lesson())

    def deploy(self, repository_root: Path = _REPOSITORY_ROOT) -> GlasshouseDemoController:
        """Compile all policies and open their deterministic two-tick live preview."""
        if self.screen not in (GlasshouseDemoScreen.WORKBENCH, GlasshouseDemoScreen.LIVE_PREVIEW):
            return self
        result = run_glasshouse_causal_drill(self.workbench, repository_root)
        if isinstance(result, GlasshouseDemoDeploymentFailure):
            return replace(
                self,
                workbench=result.workbench,
                current_run=None
                if self.screen is GlasshouseDemoScreen.LIVE_PREVIEW
                else self.current_run,
                comparison=None
                if self.screen is GlasshouseDemoScreen.LIVE_PREVIEW
                else self.comparison,
                preview_snapshot_index=0,
                preview_playing=False,
                preview_stale=False,
                notice="Deployment blocked: fix a policy compile failure.",
            )
        return self._accept_preview_run(result)

    def reload_preview(self, repository_root: Path = _REPOSITORY_ROOT) -> GlasshouseDemoController:
        """Recompile and rerun an enabled preview after one immutable source edit."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW:
            return self
        result = run_glasshouse_causal_drill(self.workbench, repository_root)
        if isinstance(result, GlasshouseDemoDeploymentFailure):
            return replace(
                self,
                workbench=result.workbench,
                current_run=None,
                comparison=None,
                preview_snapshot_index=0,
                preview_playing=False,
                preview_stale=False,
                notice="Hot reload blocked: fix the highlighted compile diagnostic.",
            )
        return self._accept_preview_run(result, notice="Hot reloaded deterministic drill.")

    def toggle_hot_reload(self) -> GlasshouseDemoController:
        """Toggle automatic compile-and-rerun after an editor change."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW:
            return self
        enabled = not self.hot_reload_enabled
        return replace(
            self,
            hot_reload_enabled=enabled,
            notice=f"Hot reload {'enabled' if enabled else 'paused'}.",
        )

    def rotate_preview(self, direction: int = 1) -> GlasshouseDemoController:
        """Rotate the renderer-only isometric view without changing a recorded run."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW:
            return self
        if (
            not isinstance(direction, int)
            or isinstance(direction, bool)
            or direction not in (-1, 1)
        ):
            raise ValueError("Glasshouse preview rotation direction must be minus or plus one")
        next_rotation = (self.preview_rotation_quarters + direction) % 4
        return replace(
            self,
            preview_rotation_quarters=next_rotation,
            notice=f"View rotated to {next_rotation * 90} degrees.",
        )

    def toggle_preview_playing(self) -> GlasshouseDemoController:
        """Pause or resume non-authoritative recorded-preview playback."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW or self.current_run is None:
            return self
        return replace(self, preview_playing=not self.preview_playing, notice="")

    def pause_preview(self) -> GlasshouseDemoController:
        """Pause non-authoritative recorded-preview playback after an explicit step."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW or self.current_run is None:
            return self
        return replace(self, preview_playing=False, notice="")

    def set_preview_snapshot(self, index: int) -> GlasshouseDemoController:
        """Select one recorded checkpoint for visual inspection without replaying authority."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW or self.current_run is None:
            return self
        if not isinstance(index, int) or isinstance(index, bool):
            raise TypeError("Glasshouse demo preview snapshot index must be an integer")
        if not 0 <= index < len(self.current_run.snapshots):
            raise ValueError("Glasshouse demo preview snapshot index is unavailable")
        selected = replace(self, preview_snapshot_index=index)
        if index == 0:
            return _focus_scout_caution_literal(selected)
        return selected._focus_preview_source()

    def select_preview_entity(self, entity_id: int) -> GlasshouseDemoController:
        """Pause on one map entity and focus its retained policy evaluation source."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW or self.current_run is None:
            return self
        if not isinstance(entity_id, int) or isinstance(entity_id, bool) or entity_id <= 0:
            raise ValueError("Glasshouse preview entity ID must be positive")
        snapshot = self.current_run.snapshots[self.preview_snapshot_index]
        if entity_id not in tuple(operative.entity_id for operative in snapshot.operatives):
            return self
        trace_tick = max(0, snapshot.tick - 1)
        intention = next(
            (
                record
                for record in self.current_run.trace.records
                if isinstance(record, IntentionTrace)
                and record.tick == trace_tick
                and record.origin.issuer_entity_id.value == entity_id
            ),
            None,
        )
        if intention is None:
            return replace(self, preview_selected_entity_id=entity_id, preview_playing=False)
        return replace(
            self,
            selected_trace_node_id=intention.node_id,
            preview_selected_entity_id=entity_id,
            preview_playing=False,
            notice=f"Entity {entity_id}: policy evaluation at t{trace_tick}.",
            workbench=self.workbench.focus_source(intention.origin.source_span),
        )

    def select_preview_source_offset(self, offset: ByteOffset) -> GlasshouseDemoController:
        """Pause at the earliest retained evaluation for a clicked source offset."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW or self.current_run is None:
            return self
        if not isinstance(offset, ByteOffset):
            raise TypeError("Glasshouse preview source offset is invalid")
        source_file_id = self.workbench.source.file_id
        record = next(
            (
                candidate
                for candidate in self.current_run.trace.records
                if isinstance(candidate, (ExpressionEvaluationTrace, IntentionTrace))
                and _record_source_span(candidate).file_id == source_file_id
                and _record_source_span(candidate).contains(offset)
            ),
            None,
        )
        if record is None:
            return self
        snapshot_index = next(
            (
                index
                for index, snapshot in enumerate(self.current_run.snapshots)
                if snapshot.tick >= record.tick + 1
            ),
            len(self.current_run.snapshots) - 1,
        )
        return replace(
            self,
            preview_snapshot_index=snapshot_index,
            selected_trace_node_id=record.node_id,
            preview_playing=False,
            notice=f"Source evaluation at t{record.tick} selected.",
        )

    def advance_preview(self) -> GlasshouseDemoController:
        """Advance one display checkpoint and loop after the final recorded tick."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW or self.current_run is None:
            return self
        return self.set_preview_snapshot(
            (self.preview_snapshot_index + 1) % len(self.current_run.snapshots)
        )

    def _accept_preview_run(
        self, result: GlasshouseDemoRun, *, notice: str | None = None
    ) -> GlasshouseDemoController:
        """Store one successful headless rerun as an independently replayable preview."""
        comparison = (
            None
            if self.baseline_run is None
            else run_comparison_view(
                self.baseline_run.recorded,
                result.recorded,
                self.baseline_run.trace,
                result.trace,
            )
        )
        baseline = result if self.baseline_run is None else self.baseline_run
        result_notice = notice or (
            "Try it: Lark's 1m decision is selected. Type 0 to prevent the exposed advance."
            if self.baseline_run is None
            else (
                "Lark was injured. Open the debrief to inspect why."
                if isinstance(result.debrief, GlasshouseDebrief)
                else "No injury retained. Compare this controlled rerun with the baseline."
            )
        )
        preview = replace(
            self,
            screen=GlasshouseDemoScreen.LIVE_PREVIEW,
            workbench=_compile_all_policies(self.workbench),
            current_run=result,
            baseline_run=baseline,
            comparison=comparison,
            preview_snapshot_index=0,
            preview_playing=True,
            preview_stale=False,
            selected_trace_node_id=None,
            preview_selected_entity_id=None,
            notice=result_notice,
        )
        return _focus_scout_caution_literal(preview)._focus_preview_source()

    def _focus_preview_source(self) -> GlasshouseDemoController:
        """Focus the current scout intention span when retained trace evidence exists."""
        span = self.preview_source_span()
        if span is None:
            return self
        return replace(self, workbench=self.workbench.focus_source(span))

    def preview_source_span(self) -> SourceSpan | None:
        """Return the selected scout's retained intention span for the shown checkpoint."""
        if self.screen is not GlasshouseDemoScreen.LIVE_PREVIEW or self.current_run is None:
            return None
        if self.preview_stale:
            return None
        if self.workbench.selected_policy.role != "scout":
            return None
        snapshot = self.current_run.snapshots[self.preview_snapshot_index]
        if snapshot.tick == 0:
            return None
        trace_tick = snapshot.tick - 1
        for record in self.current_run.trace.records:
            if (
                isinstance(record, IntentionTrace)
                and record.tick == trace_tick
                and record.origin.source_span.file_id == self.workbench.source.file_id
            ):
                return record.origin.source_span
        return None

    def open_debrief(self) -> GlasshouseDemoController:
        """Show retained causal evidence for the current completed drill."""
        if self.screen not in (GlasshouseDemoScreen.MISSION, GlasshouseDemoScreen.LIVE_PREVIEW):
            return self
        if self.current_run is None:
            raise AssertionError("mission screen has no current run")
        if not isinstance(self.current_run.debrief, GlasshouseDebrief):
            if self.comparison is not None:
                return replace(
                    self,
                    screen=GlasshouseDemoScreen.COMPARISON,
                    preview_playing=False,
                    notice="",
                )
            return replace(self, notice="No retained injury is available for this run.")
        return replace(self, screen=GlasshouseDemoScreen.DEBRIEF, preview_playing=False, notice="")

    def guide_revision(self) -> GlasshouseDemoController:
        """Navigate a retained injury back to unchanged editable scout source."""
        if self.screen is not GlasshouseDemoScreen.DEBRIEF or self.current_run is None:
            return self
        if not isinstance(self.current_run.debrief, GlasshouseDebrief):
            return replace(self, notice="No retained injury is available for revision.")
        revision = guided_source_revision(
            self.current_run.debrief,
            self.current_run.trace,
            self.current_run.archive,
            self.workbench,
        )
        if isinstance(revision, GlasshouseGuidedRevision):
            return replace(
                self,
                screen=GlasshouseDemoScreen.WORKBENCH,
                workbench=revision.workbench,
                notice="Causal source selected. Replace only 1m with 0m, then deploy again.",
            )
        return replace(self, notice=_guided_revision_notice(revision))

    def open_comparison(self) -> GlasshouseDemoController:
        """Open the compatibility-gated baseline comparison after a controlled rerun."""
        if self.current_run is None or self.comparison is None:
            return self
        return replace(self, screen=GlasshouseDemoScreen.COMPARISON, notice="")

    def return_to_workbench(self) -> GlasshouseDemoController:
        """Return to source editing without changing any recorded run."""
        if self.screen not in (
            GlasshouseDemoScreen.LIVE_PREVIEW,
            GlasshouseDemoScreen.MISSION,
            GlasshouseDemoScreen.DEBRIEF,
            GlasshouseDemoScreen.COMPARISON,
        ):
            return self
        return replace(
            self, screen=GlasshouseDemoScreen.WORKBENCH, preview_playing=False, notice=""
        )


def _record_source_span(record: ExpressionEvaluationTrace | IntentionTrace) -> SourceSpan:
    """Return source provenance from one retained source-bearing trace record."""
    return (
        record.source_span
        if isinstance(record, ExpressionEvaluationTrace)
        else record.origin.source_span
    )


def _focus_scout_caution_literal(
    controller: GlasshouseDemoController,
) -> GlasshouseDemoController:
    """Select the editable scout caution numeral in presentation state."""
    scout = controller.workbench.select_policy("scout")
    span = _scout_caution_span(scout.source)
    return replace(controller, workbench=scout if span is None else scout.focus_source(span))


def _scout_caution_span(source: SourceFile) -> SourceSpan | None:
    """Return the shipped `1` inside the scout's `<= 1m` caution literal."""
    marker = "<= 1m"
    marker_start = source.text.find(marker)
    if marker_start < 0:
        return None
    start = marker_start + len("<= ")
    return source.span(
        ByteOffset(len(source.text[:start].encode("utf-8"))),
        ByteOffset(len(source.text[: start + 1].encode("utf-8"))),
    )


def load_glasshouse_workbench(repository_root: Path = _REPOSITORY_ROOT) -> GlasshouseWorkbench:
    """Read the four shipped player policies at the application IO boundary."""
    if not isinstance(repository_root, Path):
        raise TypeError("Glasshouse demo repository root must be a path")
    source_ids = tuple(
        "examples/policies/glasshouse/" + name + ".dtr"
        for name in ("breacher", "medic", "overwatch", "scout")
    )
    sources = tuple(_read_source(repository_root, source_id) for source_id in source_ids)
    return build_glasshouse_workbench(sources)


def run_glasshouse_causal_drill(
    workbench: GlasshouseWorkbench,
    repository_root: Path = _REPOSITORY_ROOT,
) -> GlasshouseDemoDeploymentResult:
    """Record the explainable two-tick scout threshold drill from current source buffers."""
    if not isinstance(workbench, GlasshouseWorkbench):
        raise TypeError("Glasshouse causal drill requires a workbench")
    if workbench.phase is not GlasshouseFlowPhase.WORKBENCH:
        raise ValueError("Glasshouse causal drill requires an open workbench")
    if not isinstance(repository_root, Path):
        raise TypeError("Glasshouse causal drill repository root must be a path")
    compiled = _compile_all_policies(workbench)
    if any(output is None or not output.succeeded for output in compiled.compile_outputs):
        return GlasshouseDemoDeploymentFailure(compiled)
    scout = compiled.select_policy("scout")
    scout_output = scout.compile_output
    if scout_output is None or scout_output.artifact is None:
        raise AssertionError("successful scout compile output has no artifact")
    enemy_source = _read_source(repository_root, _ENEMY_SOURCE_ID)
    enemy_artifact = _compile_trusted_source(enemy_source)
    initial_state, player, enemy = _build_drill_initial_state()
    bindings = PolicyBindings(
        (
            PolicyBinding(
                player.entity_id,
                scout_output.artifact,
                _entry_function_id(scout_output.artifact),
                PLAYER_MEMORY_SCHEMA,
                RecordValue("Memory", ("label",), (StringValue("scout"),)),
            ),
            PolicyBinding(
                enemy.entity_id,
                enemy_artifact,
                _entry_function_id(enemy_artifact),
                _ENEMY_MEMORY_SCHEMA,
                RecordValue("Memory", ("fired",), (BooleanValue(False),)),
            ),
        )
    )
    recorded = record_headless_run(
        initial_state,
        FixedTickClock(TickRate.HZ_30),
        _DEMO_TICKS,
        application_build=_DEMO_APPLICATION_BUILD,
        simulation_version=_DEMO_SIMULATION_VERSION,
        mission_hash=_DEMO_MISSION_HASH,
        commands=(StartMission(CommandHeader(0, 0, CommandSource.SCENARIO)),),
        policy_bindings=bindings,
    )
    trace = capture_run_trace(recorded.run, hash_canonical_state(recorded.run.state))
    sources = tuple(sorted((scout.source, enemy_source), key=lambda source: source.file_id))
    archive = build_source_archive(
        recorded.replay,
        tuple(
            HistoricalSourceFile(source, _source_language_version(bindings, source))
            for source in sources
        ),
        bindings,
    )
    snapshots = _presentation_snapshots(recorded)
    return GlasshouseDemoRun(recorded, trace, archive, snapshots, glasshouse_debrief(trace))


def _presentation_snapshots(recorded: RecordedReplay) -> tuple[PresentationSnapshot, ...]:
    """Copy each retained replay checkpoint into one renderer-safe tactical snapshot."""
    snapshots: list[PresentationSnapshot] = []
    for checkpoint in recorded.run.checkpoints:
        restored = restore_authority_snapshot(checkpoint)
        if isinstance(restored, SnapshotRestoreFailure):
            raise AssertionError("recorded Glasshouse checkpoint cannot be restored")
        event_tick = checkpoint.tick - 1
        events = (
            ()
            if event_tick < 0
            else tuple(event for event in recorded.run.events if event.header.tick == event_tick)
        )
        snapshots.append(build_presentation_snapshot(restored, projectile_events=events))
    return tuple(snapshots)


def _compile_all_policies(workbench: GlasshouseWorkbench) -> GlasshouseWorkbench:
    selected_role = workbench.selected_policy.role
    compiled = workbench
    for policy in compiled.policies:
        compiled = compiled.select_policy(policy.role).compile_selected()
    return compiled.select_policy(selected_role)


def _build_drill_initial_state() -> tuple[MissionState, EntityState, EntityState]:
    geometry = MapGeometry(
        WorldRectangle(
            WorldSubunits(-5_000),
            WorldSubunits(-5_000),
            WorldSubunits(5_000),
            WorldSubunits(5_000),
        )
    )
    state, player = add_entity(
        MissionState(map_geometry=geometry), WorldPosition(WorldSubunits(0), WorldSubunits(0))
    )
    state, enemy = add_entity(state, WorldPosition(WorldSubunits(2_500), WorldSubunits(0)))
    cover_id, allocator = state.id_allocator.allocate_cover()
    evidence_event_id, allocator = allocator.allocate_event()
    contact_id, allocator = allocator.allocate_contact()
    weapon_id, allocator = allocator.allocate_weapon()
    cover = CoverSegment(
        cover_id,
        WorldPosition(WorldSubunits(-500), WorldSubunits(-700)),
        WorldPosition(WorldSubunits(500), WorldSubunits(-700)),
        CoverHeight.HIGH,
        CoverIntegrity(10_000),
        (CoverSlot(0, WorldPosition(WorldSubunits(0), WorldSubunits(-350)), CoverSide.LEFT),),
    )
    contact = ContactEstimate(
        contact_id,
        player.entity_id,
        enemy.position,
        WorldSubunits(500),
        ContactConfidence(10_000),
        0,
        ContactProvenance(
            tuple(ContactFieldProvenance(field, (evidence_event_id,)) for field in ContactField)
        ),
    )
    return (
        replace(
            state,
            id_allocator=allocator,
            contacts=ContactStore((contact,)),
            covers=CoverStore((cover,)),
            conditions=OperativeConditionStore((OperativeCondition(player.entity_id, 1, 0),)),
            weapons=WeaponStore((EquippedWeapon(weapon_id, enemy.entity_id, Ammunition(1, 1)),)),
        ),
        player,
        enemy,
    )


def _read_source(repository_root: Path, source_id: str) -> SourceFile:
    path = repository_root / source_id
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(f"could not read Glasshouse demo policy {path}") from error
    return SourceFile(SourceFileId(source_id), text)


def _compile_trusted_source(source: SourceFile) -> CompiledArtifact:
    parsed = parse(lex(source))
    if parsed.diagnostics:
        raise AssertionError("shipped Glasshouse demo source has parse diagnostics")
    checked = check(resolve(parsed.module))
    if checked.diagnostics or checked.module is None:
        raise AssertionError("shipped Glasshouse demo source has check diagnostics")
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))


def _entry_function_id(artifact: CompiledArtifact) -> FunctionId:
    if len(artifact.capability_manifest.entries) != 1:
        raise AssertionError("Glasshouse demo policy must have one entry point")
    return artifact.capability_manifest.entries[0].function_id


def _source_language_version(bindings: PolicyBindings, source: SourceFile) -> int:
    for binding in bindings.entries:
        header = binding.artifact.bytecode.header
        if header.source_file_id == source.file_id:
            return header.source_language_version
    raise AssertionError("Glasshouse demo source has no policy binding")


def _guided_revision_notice(result: GuidedRevisionResult) -> str:
    return "Guided source revision is unavailable for this retained outcome."
