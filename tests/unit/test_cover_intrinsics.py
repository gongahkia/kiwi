from __future__ import annotations

from kiwi.domain.quantities import ExactRational, Quantity, QuantityDimension
from kiwi.dsl.bytecode import BytecodeHeader, PushIntrinsic
from kiwi.dsl.bytecode_codec import decode_bytecode, encode_bytecode
from kiwi.dsl.checker import check
from kiwi.dsl.compiler import compile_core
from kiwi.dsl.ids import FunctionId
from kiwi.dsl.intrinsics import IntrinsicKind
from kiwi.dsl.lexer import lex
from kiwi.dsl.lower import lower
from kiwi.dsl.names import resolve
from kiwi.dsl.parser import parse
from kiwi.dsl.runtime_values import (
    IntegerValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    StringValue,
)
from kiwi.dsl.source import SourceFile, SourceFileId
from kiwi.dsl.vm import (
    CoverCandidateRejectionReason,
    CoverCandidateTraceStatus,
    VMBudgets,
    VMFaultCode,
    run_vm,
)


def test_cover_intrinsics_compile_encode_and_rank_safe_slots_deterministically() -> None:
    source = SourceFile(SourceFileId("cover-intrinsics.dtr"), _SOURCE)

    checked = check(resolve(parse(lex(source)).module))

    assert checked.diagnostics == ()
    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    assert {
        instruction.intrinsic
        for function in module.functions
        for instruction in function.instructions
        if isinstance(instruction, PushIntrinsic)
    } == {
        IntrinsicKind.COVER_EXPOSURE,
        IntrinsicKind.COVER_ROUTE_COST,
        IntrinsicKind.COVER_NEAREST_SAFE,
        IntrinsicKind.COVER_SEEK,
    }
    assert decode_bytecode(encode_bytecode(module)) == module

    assert run_vm(module, FunctionId(0), ()).value == IntegerValue(2_500)
    assert run_vm(module, FunctionId(1), ()).value == QuantityValue(
        Quantity(QuantityDimension.DISTANCE, ExactRational(2, 1))
    )
    assert run_vm(module, FunctionId(2), ()).value == OptionSomeValue(
        RecordValue("TakeCover", ("cover_id", "side"), (IntegerValue(2), StringValue("left")))
    )
    assert run_vm(module, FunctionId(3), ()).value == RecordValue(
        "TakeCover", ("cover_id", "side"), (IntegerValue(2), StringValue("right"))
    )


def test_cover_intrinsics_reject_non_direct_calls_bad_arities_and_bad_schemas() -> None:
    source = SourceFile(
        SourceFileId("cover-intrinsics-invalid.dtr"),
        "type TakeCover = { cover_id: Int, side: String }\n"
        "type CoverSlot = { position: Position, side: String, slot_index: Int }\n"
        "type Cover = { cover_id: String, end: Position, height: String, "
        "integrity_basis_points: Int, slots: List<CoverSlot>, start: Position }\n"
        "type Contact = { age_ticks: Int, confidence_basis_points: Int, contact_id: Int, "
        "estimated_position: Position, uncertainty_radius: Distance }\n"
        "fn reference() -> Int = Cover.seek\n"
        "fn arity() -> TakeCover = Cover.seek(1)\n"
        "fn schema(cover: Cover, position: Position, contact: Contact) -> Option<TakeCover> = "
        "Cover.nearest_safe([cover], position, contact)\n",
    )

    result = check(resolve(parse(lex(source)).module))

    assert result.module is None
    assert tuple(diagnostic.code for diagnostic in result.diagnostics) == (
        "E424_INTRINSIC_CALL",
        "E430_COVER_ARITY",
        "E432_COVER_SCHEMA",
    )


def test_cover_nearest_safe_charges_bounded_candidate_work() -> None:
    source = SourceFile(SourceFileId("cover-intrinsics-budget.dtr"), _SOURCE)
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    result = run_vm(module, FunctionId(2), (), VMBudgets(instruction_limit=60))

    assert result.fault is not None
    assert result.fault.code is VMFaultCode.INSTRUCTION_BUDGET
    assert result.fault.source_map_entry is not None


def test_cover_nearest_safe_trace_retains_scores_rejections_and_source() -> None:
    source = SourceFile(SourceFileId("cover-intrinsics-trace.dtr"), _SOURCE)
    checked = check(resolve(parse(lex(source)).module))

    assert checked.module is not None
    module = compile_core(lower(checked.module).module, BytecodeHeader(source.file_id))
    untraced = run_vm(module, FunctionId(2), ())
    result = run_vm(module, FunctionId(2), (), capture_cover_selection_trace=True)
    standard = run_vm(module, FunctionId(2), (), capture_standard_library_trace=True)
    repeated = run_vm(module, FunctionId(2), (), capture_cover_selection_trace=True)
    trace = result.cover_selection_traces[0]

    assert result.succeeded
    assert untraced.value == result.value
    assert untraced.cover_selection_traces == ()
    assert result.cover_selection_traces == repeated.cover_selection_traces
    assert standard.cover_selection_traces == result.cover_selection_traces
    assert standard.standard_library_decision_traces == ()
    assert trace.source_map_entry.span.file_id == source.file_id
    assert trace.source_map_entry.span.start.value == source.text.index("Cover.nearest_safe")
    assert tuple(
        (
            candidate.cover_id,
            candidate.slot_index,
            candidate.exposure_basis_points,
            candidate.route_cost.value,
            candidate.status,
            candidate.rejection_reason,
        )
        for candidate in trace.candidates
    ) == (
        (
            2,
            0,
            2_500,
            ExactRational(12, 1),
            CoverCandidateTraceStatus.SELECTED,
            None,
        ),
        (
            2,
            1,
            2_500,
            ExactRational(12, 1),
            CoverCandidateTraceStatus.REJECTED,
            CoverCandidateRejectionReason.HIGHER_SLOT_INDEX,
        ),
        (
            3,
            0,
            2_500,
            ExactRational(12, 1),
            CoverCandidateTraceStatus.REJECTED,
            CoverCandidateRejectionReason.HIGHER_COVER_ID,
        ),
        (
            2,
            2,
            2_500,
            ExactRational(13, 1),
            CoverCandidateTraceStatus.REJECTED,
            CoverCandidateRejectionReason.HIGHER_ROUTE_COST,
        ),
        (
            1,
            0,
            5_000,
            ExactRational(12, 1),
            CoverCandidateTraceStatus.REJECTED,
            CoverCandidateRejectionReason.HIGHER_EXPOSURE,
        ),
    )


_SOURCE = """\
type CoverSlot = {
  position: Position,
  side: String,
  slot_index: Int
}
type Cover = {
  cover_id: Int,
  end: Position,
  height: String,
  integrity_basis_points: Int,
  slots: List<CoverSlot>,
  start: Position
}
type Contact = {
  age_ticks: Int,
  confidence_basis_points: Int,
  contact_id: Int,
  estimated_position: Position,
  uncertainty_radius: Distance
}
type TakeCover = { cover_id: Int, side: String }
policy exposure() -> Int =
  Cover.exposure(
    Cover {
      cover_id = 1,
      end = Position { x = 10m, y = 10m },
      height = "high",
      integrity_basis_points = 10000,
      slots = [
        CoverSlot {
          position = Position { x = 1m, y = 1m },
          side = "left",
          slot_index = 0
        }
      ],
      start = Position { x = 0m, y = 10m }
    },
    CoverSlot {
      position = Position { x = 1m, y = 1m },
      side = "left",
      slot_index = 0
    },
    Contact {
      age_ticks = 0,
      confidence_basis_points = 10000,
      contact_id = 1,
      estimated_position = Position { x = 0m, y = 0m },
      uncertainty_radius = 0m
    }
  )
policy route_cost() -> Distance =
  Cover.route_cost(
  Position { x = 0m, y = 0m },
  CoverSlot {
    position = Position { x = 2m, y = 0m },
    side = "left",
    slot_index = 0
  }
)
policy nearest_safe() -> Option<TakeCover> =
  Cover.nearest_safe(
    [
      Cover {
        cover_id = 1,
        end = Position { x = 10m, y = 10m },
        height = "low",
        integrity_basis_points = 10000,
        slots = [
          CoverSlot {
            position = Position { x = 1m, y = 11m },
            side = "left",
            slot_index = 0
          }
        ],
        start = Position { x = 0m, y = 10m }
      },
      Cover {
        cover_id = 2,
        end = Position { x = 10m, y = 10m },
        height = "high",
        integrity_basis_points = 10000,
        slots = [
          CoverSlot {
            position = Position { x = 2m, y = 10m },
            side = "left",
            slot_index = 0
          },
          CoverSlot {
            position = Position { x = 1m, y = 11m },
            side = "left",
            slot_index = 1
          },
          CoverSlot {
            position = Position { x = 3m, y = 10m },
            side = "left",
            slot_index = 2
          }
        ],
        start = Position { x = 0m, y = 10m }
      },
      Cover {
        cover_id = 3,
        end = Position { x = 10m, y = 10m },
        height = "high",
        integrity_basis_points = 10000,
        slots = [
          CoverSlot {
            position = Position { x = 2m, y = 10m },
            side = "left",
            slot_index = 0
          }
        ],
        start = Position { x = 0m, y = 10m }
      }
    ],
    Position { x = 0m, y = 0m },
    Contact {
      age_ticks = 0,
      confidence_basis_points = 10000,
      contact_id = 1,
      estimated_position = Position { x = 0m, y = 0m },
      uncertainty_radius = 0m
    }
  )
policy seek() -> TakeCover = Cover.seek(2, "right")
"""
