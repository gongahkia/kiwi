from __future__ import annotations

from pathlib import Path

from kiwi.domain.geometry import WorldPosition, WorldSubunits
from kiwi.domain.ids import PolicyInvocationId
from kiwi.dsl.bytecode import BytecodeHeader
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import CompiledArtifact, compile_artifact
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.policy_result import MemoryField, MemorySchema
from kiwi.dsl.runtime_values import RecordValue, StringValue
from kiwi.dsl.source import ByteOffset, SourceFile, SourceFileId
from kiwi.dsl.types import BuiltinType
from kiwi.sim.clock import FixedTickClock, TickRate
from kiwi.sim.commands import CommandHeader, CommandSource, StartMission
from kiwi.sim.events import IntentionEmitted, IntentionSelected, PolicyEvaluated
from kiwi.sim.hashing import hash_canonical_state
from kiwi.sim.policies import PolicyBinding, PolicyBindings
from kiwi.sim.runner import run_headless
from kiwi.sim.state import MissionState, add_entity

FIXTURE_PATH = Path(__file__).resolve().parents[1] / "fixtures" / "policies" / "wait_policy.dtr"
MEMORY_SCHEMA = MemorySchema("Memory", (MemoryField("label", BuiltinType.STRING),))


def test_compiled_wait_fixture_changes_headless_events_deterministically() -> None:
    source = SourceFile(
        SourceFileId("tests/fixtures/policies/wait_policy.dtr"),
        FIXTURE_PATH.read_text(encoding="utf-8"),
    )
    artifact = _compile(source)
    state, entity = add_entity(MissionState(), WorldPosition(WorldSubunits(10), WorldSubunits(20)))
    bindings = PolicyBindings(
        (
            PolicyBinding(
                entity.entity_id,
                artifact,
                FunctionId(0),
                MEMORY_SCHEMA,
                RecordValue("Memory", ("label",), (StringValue("ready"),)),
            ),
        )
    )
    start = StartMission(CommandHeader(0, 0, CommandSource.SCENARIO))
    clock = FixedTickClock(TickRate.HZ_30)

    first = run_headless(
        state,
        clock,
        2,
        (start,),
        checkpoint_interval=1,
        policy_bindings=bindings,
    )
    second = run_headless(
        state,
        clock,
        2,
        (start,),
        checkpoint_interval=1,
        policy_bindings=bindings,
    )

    policy_events = tuple(event for event in first.events if isinstance(event, PolicyEvaluated))
    emitted = tuple(event for event in first.events if isinstance(event, IntentionEmitted))
    selected = tuple(event for event in first.events if isinstance(event, IntentionSelected))
    wait_text = "Wait { duration = 1s }"
    wait_start = source.text.index(wait_text)

    assert first.events == second.events
    assert first.checkpoints == second.checkpoints
    assert hash_canonical_state(first.state) == hash_canonical_state(second.state)
    assert tuple(event.validation.evaluation.invocation_id for event in policy_events) == (
        PolicyInvocationId(1),
        PolicyInvocationId(2),
    )
    assert len(emitted) == len(selected) == 2
    assert all(event.candidate.origin.issuer_entity_id == entity.entity_id for event in emitted)
    assert all(
        event.candidate.origin.source_span
        == source.span(ByteOffset(wait_start), ByteOffset(wait_start + len(wait_text)))
        for event in emitted
    )
    assert all(
        event.resolution.candidate.origin.source_expression_id
        == emitted[index].candidate.origin.source_expression_id
        for index, event in enumerate(selected)
    )
    assert first.state.policy_memory.memory_for(entity.entity_id) == RecordValue(
        "Memory", ("label",), (StringValue("ready"),)
    )
    assert (
        first.state.policy_versions.version_for(entity.entity_id)
        == bindings.entries[0].policy_version
    )


def _compile(source: SourceFile) -> CompiledArtifact:
    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    return compile_artifact(lower(checked.module).module, BytecodeHeader(source.file_id))
