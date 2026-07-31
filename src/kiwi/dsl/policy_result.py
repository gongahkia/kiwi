"""Pure validation for policy memory and decision boundary values."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from kiwi.domain.quantities import QuantityDimension
from kiwi.dsl.runtime_values import (
    BooleanValue,
    IntegerValue,
    ListValue,
    OptionNoneValue,
    OptionSomeValue,
    QuantityValue,
    RecordValue,
    RuntimeValue,
    StringValue,
    UnitValue,
)
from kiwi.dsl.types import (
    BuiltinType,
    DslType,
    FunctionType,
    ListType,
    NamedType,
    OptionType,
    render_type,
)


class PolicyResultValidationCode(StrEnum):
    """Stable faults for policy boundary values."""

    MEMORY_SHAPE = "R007_MEMORY_SHAPE"
    INTENTION_SHAPE = "R008_INTENTION_SHAPE"


@dataclass(frozen=True, slots=True)
class MemoryField:
    """One lexically ordered field accepted in persistent policy memory."""

    name: str
    type_: DslType

    def __post_init__(self) -> None:
        if not isinstance(self.name, str) or not self.name:
            raise ValueError("memory field name must be a non-empty string")
        if not _is_dsl_type(self.type_):
            raise ValueError("memory field type must be a DSL type")
        if _contains_function_type(self.type_):
            raise ValueError("memory fields must use data types, not function types")


@dataclass(frozen=True, slots=True)
class MemorySchema:
    """A closed nominal schema supplied by the policy invocation boundary."""

    type_name: str
    fields: tuple[MemoryField, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.type_name, str) or not self.type_name:
            raise ValueError("memory schema type name must be a non-empty string")
        if not isinstance(self.fields, tuple):
            raise ValueError("memory schema fields must be an immutable tuple")
        if any(not isinstance(field, MemoryField) for field in self.fields):
            raise ValueError("memory schema fields must be memory fields")
        names = tuple(field.name for field in self.fields)
        if names != tuple(sorted(names)) or len(set(names)) != len(names):
            raise ValueError("memory schema fields must be unique and lexically ordered")


@dataclass(frozen=True, slots=True)
class PolicyResultValidationFailure:
    """A structured policy-boundary failure with deterministic field path."""

    code: PolicyResultValidationCode
    message: str
    path: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class ValidatedPolicyResult:
    """A structurally safe decision before capability-specific intent validation."""

    memory: RecordValue
    intentions: tuple[RuntimeValue, ...]


type MemoryValidationResult = RecordValue | PolicyResultValidationFailure
type PolicyResultValidationResult = ValidatedPolicyResult | PolicyResultValidationFailure


def validate_memory(value: RuntimeValue, schema: MemorySchema) -> MemoryValidationResult:
    """Validate one persistent memory record against its explicit data schema."""
    if not isinstance(value, RecordValue) or value.type_name != schema.type_name:
        return PolicyResultValidationFailure(
            PolicyResultValidationCode.MEMORY_SHAPE,
            f"memory must be a {schema.type_name} record",
        )
    expected_names = tuple(field.name for field in schema.fields)
    if value.field_names != expected_names:
        return PolicyResultValidationFailure(
            PolicyResultValidationCode.MEMORY_SHAPE,
            "memory fields do not match the configured schema",
        )
    for field in schema.fields:
        field_value = value.field_value(field.name)
        if field_value is None or not _matches_type(field_value, field.type_):
            return PolicyResultValidationFailure(
                PolicyResultValidationCode.MEMORY_SHAPE,
                f"memory field '{field.name}' must have type {render_type(field.type_)}",
                (field.name,),
            )
    return value


def validate_policy_result(
    value: RuntimeValue,
    memory_schema: MemorySchema,
) -> PolicyResultValidationResult:
    """Validate `Decision { memory, intentions }` without resolving actions."""
    if not isinstance(value, RecordValue) or value.type_name != "Decision":
        return PolicyResultValidationFailure(
            PolicyResultValidationCode.INTENTION_SHAPE,
            "policy result must be a Decision record",
        )
    if value.field_names != ("intentions", "memory"):
        return PolicyResultValidationFailure(
            PolicyResultValidationCode.INTENTION_SHAPE,
            "Decision fields must be exactly intentions and memory",
        )
    memory_value = value.field_value("memory")
    if memory_value is None:
        raise AssertionError("Decision memory field is missing after field validation")
    memory = validate_memory(memory_value, memory_schema)
    if isinstance(memory, PolicyResultValidationFailure):
        return PolicyResultValidationFailure(memory.code, memory.message, ("memory",) + memory.path)
    intentions = value.field_value("intentions")
    if not isinstance(intentions, ListValue):
        return PolicyResultValidationFailure(
            PolicyResultValidationCode.INTENTION_SHAPE,
            "Decision.intentions must be a List value",
            ("intentions",),
        )
    return ValidatedPolicyResult(memory, intentions.values)


def _contains_function_type(type_: DslType) -> bool:
    if isinstance(type_, FunctionType):
        return True
    if isinstance(type_, (OptionType, ListType)):
        return _contains_function_type(type_.element_type)
    return False


def _matches_type(value: RuntimeValue, type_: DslType) -> bool:
    if type_ is BuiltinType.INT:
        return isinstance(value, IntegerValue)
    if type_ is BuiltinType.BOOL:
        return isinstance(value, BooleanValue)
    if type_ is BuiltinType.UNIT:
        return isinstance(value, UnitValue)
    if type_ is BuiltinType.STRING:
        return isinstance(value, StringValue)
    if type_ is BuiltinType.DURATION:
        return (
            isinstance(value, QuantityValue) and value.value.dimension is QuantityDimension.DURATION
        )
    if type_ is BuiltinType.DISTANCE:
        return (
            isinstance(value, QuantityValue) and value.value.dimension is QuantityDimension.DISTANCE
        )
    if type_ is BuiltinType.ANGLE:
        return isinstance(value, QuantityValue) and value.value.dimension is QuantityDimension.ANGLE
    if type_ is BuiltinType.PROBABILITY:
        return (
            isinstance(value, QuantityValue)
            and value.value.dimension is QuantityDimension.PROBABILITY
        )
    if isinstance(type_, OptionType):
        return isinstance(value, OptionNoneValue) or (
            isinstance(value, OptionSomeValue) and _matches_type(value.value, type_.element_type)
        )
    if isinstance(type_, ListType):
        return isinstance(value, ListValue) and all(
            _matches_type(item, type_.element_type) for item in value.values
        )
    if isinstance(type_, NamedType):
        return isinstance(value, RecordValue) and value.type_name == type_.name
    return False


def _is_dsl_type(value: object) -> bool:
    return isinstance(value, (BuiltinType, FunctionType, ListType, NamedType, OptionType))
