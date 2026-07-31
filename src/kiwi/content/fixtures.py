"""Strict JSON loader for the minimal versioned headless-kernel fixtures."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldSubunits

KERNEL_FIXTURE_FORMAT = "kiwi-kernel-fixture"
KERNEL_FIXTURE_VERSION = 1
MAX_FIXTURE_BYTES = 1_048_576
MAX_FIXTURE_ENTITIES = 65_536
MAX_FIXTURE_SCHEDULED_TRIGGERS = 65_536
MAX_FIXTURE_NESTING = 16
MAX_UINT64 = (1 << 64) - 1
MAX_TICK = (1 << 63) - 1
SUPPORTED_TICK_RATES = frozenset((20, 30, 60))


class FixtureDiagnosticCode(StrEnum):
    """Stable fixture loader and validation diagnostic codes."""

    READ_FAILED = "F001_READ_FAILED"
    TOO_LARGE = "F002_TOO_LARGE"
    INVALID_UTF8 = "F003_INVALID_UTF8"
    INVALID_JSON = "F004_INVALID_JSON"
    DUPLICATE_FIELD = "F005_DUPLICATE_FIELD"
    TOO_DEEP = "F006_TOO_DEEP"
    TOP_LEVEL_TYPE = "F007_TOP_LEVEL_TYPE"
    UNKNOWN_FIELD = "F008_UNKNOWN_FIELD"
    MISSING_FIELD = "F009_MISSING_FIELD"
    INVALID_TYPE = "F010_INVALID_TYPE"
    INVALID_VALUE = "F011_INVALID_VALUE"
    UNSUPPORTED_VERSION = "F012_UNSUPPORTED_VERSION"
    TOO_MANY_ITEMS = "F013_TOO_MANY_ITEMS"


@dataclass(frozen=True, slots=True)
class FixtureDiagnostic:
    """One stable validation diagnostic with a JSON-path provenance location."""

    code: FixtureDiagnosticCode
    path: str
    message: str


@dataclass(frozen=True, slots=True)
class FixtureLoadFailure:
    """The structured failure returned for untrusted fixture content."""

    source: str
    diagnostics: tuple[FixtureDiagnostic, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.source, str):
            raise ValueError("fixture failure source must be text")
        if not isinstance(self.diagnostics, tuple) or not self.diagnostics:
            raise ValueError("fixture failure requires immutable diagnostics")


@dataclass(frozen=True, slots=True)
class FixtureEntity:
    """One content-keyed entity spawn in canonical content-key order."""

    content_id: str
    position: WorldPosition

    def __post_init__(self) -> None:
        if not _is_identifier(self.content_id):
            raise ValueError("fixture entity content ID must be a lowercase ASCII identifier")
        if not isinstance(self.position, WorldPosition):
            raise ValueError("fixture entity requires a world position")


@dataclass(frozen=True, slots=True)
class KernelFixture:
    """Validated primitive authority inputs for the Milestone 5 simulation kernel."""

    fixture_id: str
    tick_rate: int
    seed: int
    entities: tuple[FixtureEntity, ...]
    scheduled_trigger_ticks: tuple[int, ...]

    def __post_init__(self) -> None:
        if not _is_identifier(self.fixture_id):
            raise ValueError("fixture ID must be a lowercase ASCII identifier")
        if not isinstance(self.tick_rate, int) or isinstance(self.tick_rate, bool):
            raise ValueError("fixture tick rate must be an integer")
        if self.tick_rate not in SUPPORTED_TICK_RATES:
            raise ValueError("fixture tick rate must be one of 20, 30, or 60")
        if not isinstance(self.seed, int) or isinstance(self.seed, bool):
            raise ValueError("fixture seed must be an integer")
        if not 0 <= self.seed <= MAX_UINT64:
            raise ValueError("fixture seed must fit unsigned 64-bit range")
        if not isinstance(self.entities, tuple):
            raise ValueError("fixture entities must be an immutable tuple")
        if len(self.entities) > MAX_FIXTURE_ENTITIES:
            raise ValueError("fixture entity count exceeds the configured limit")
        previous_id = ""
        for entity in self.entities:
            if not isinstance(entity, FixtureEntity):
                raise ValueError("fixture entities must be fixture entities")
            if entity.content_id <= previous_id:
                raise ValueError("fixture entities must be in unique canonical content-ID order")
            previous_id = entity.content_id
        if not isinstance(self.scheduled_trigger_ticks, tuple):
            raise ValueError("fixture scheduled triggers must be an immutable tuple")
        if len(self.scheduled_trigger_ticks) > MAX_FIXTURE_SCHEDULED_TRIGGERS:
            raise ValueError("fixture scheduled trigger count exceeds the configured limit")
        previous_tick = -1
        for tick in self.scheduled_trigger_ticks:
            if not isinstance(tick, int) or isinstance(tick, bool):
                raise ValueError("fixture scheduled trigger ticks must be integers")
            if not 0 <= tick <= MAX_TICK:
                raise ValueError("fixture scheduled trigger tick must fit signed 64-bit range")
            if tick < previous_tick:
                raise ValueError("fixture scheduled trigger ticks must be canonically ordered")
            previous_tick = tick


type FixtureLoadResult = KernelFixture | FixtureLoadFailure


def load_kernel_fixture_file(path: Path) -> FixtureLoadResult:
    """Read and validate one bounded UTF-8 kernel fixture file."""
    if not isinstance(path, Path):
        raise TypeError("fixture path must be a Path")
    try:
        data = path.read_bytes()
    except OSError:
        return _failure(str(path), FixtureDiagnosticCode.READ_FAILED, "$", "could not read fixture")
    return load_kernel_fixture_bytes(data, str(path))


def load_kernel_fixture_bytes(data: bytes, source: str = "<bytes>") -> FixtureLoadResult:
    """Validate one bounded JSON fixture without importing simulation or pygame."""
    if not isinstance(data, bytes):
        raise TypeError("fixture data must be bytes")
    if not isinstance(source, str):
        raise TypeError("fixture source must be text")
    if len(data) > MAX_FIXTURE_BYTES:
        return _failure(
            source,
            FixtureDiagnosticCode.TOO_LARGE,
            "$",
            "fixture exceeds the configured byte limit",
        )
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return _failure(
            source, FixtureDiagnosticCode.INVALID_UTF8, "$", "fixture is not valid UTF-8"
        )
    try:
        document = json.loads(text, object_pairs_hook=_reject_duplicate_fields)
    except json.JSONDecodeError:
        return _failure(
            source, FixtureDiagnosticCode.INVALID_JSON, "$", "fixture is not valid JSON"
        )
    except _DuplicateFieldError as error:
        return _failure(
            source,
            FixtureDiagnosticCode.DUPLICATE_FIELD,
            "$",
            f"duplicate JSON object field {error.field!r}",
        )
    except RecursionError:
        return _failure(
            source, FixtureDiagnosticCode.TOO_DEEP, "$", "fixture nesting exceeds limit"
        )
    try:
        _validate_nesting(document, 0)
        return _parse_fixture(document)
    except _FixtureError as error:
        return _failure(source, error.code, error.path, error.message)


def _parse_fixture(document: object) -> KernelFixture:
    root = _require_mapping(document, "$")
    _require_fields(
        root,
        "$",
        frozenset(
            ("format", "version", "id", "tick_rate", "seed", "entities", "scheduled_triggers")
        ),
    )
    format_name = _require_string(root["format"], "$.format")
    if format_name != KERNEL_FIXTURE_FORMAT:
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_VALUE, "$.format", "fixture format is invalid"
        )
    version = _require_integer(root["version"], "$.version")
    if version != KERNEL_FIXTURE_VERSION:
        raise _FixtureError(
            FixtureDiagnosticCode.UNSUPPORTED_VERSION,
            "$.version",
            f"unsupported fixture version {version}",
        )
    fixture_id = _require_identifier(root["id"], "$.id")
    tick_rate = _require_integer(root["tick_rate"], "$.tick_rate")
    if tick_rate not in SUPPORTED_TICK_RATES:
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_VALUE,
            "$.tick_rate",
            "fixture tick rate must be one of 20, 30, or 60",
        )
    seed = _require_integer(root["seed"], "$.seed")
    if not 0 <= seed <= MAX_UINT64:
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_VALUE,
            "$.seed",
            "fixture seed must fit unsigned 64-bit range",
        )
    entities = _parse_entities(_require_mapping(root["entities"], "$.entities"))
    trigger_ticks = _parse_trigger_ticks(root["scheduled_triggers"], "$.scheduled_triggers")
    return KernelFixture(fixture_id, tick_rate, seed, entities, trigger_ticks)


def _parse_entities(value: dict[str, object]) -> tuple[FixtureEntity, ...]:
    if len(value) > MAX_FIXTURE_ENTITIES:
        raise _FixtureError(
            FixtureDiagnosticCode.TOO_MANY_ITEMS,
            "$.entities",
            "fixture entity count exceeds the configured limit",
        )
    entities: list[FixtureEntity] = []
    for content_id in sorted(value):
        path = f"$.entities.{content_id}"
        entity_id = _require_identifier(content_id, path)
        entity = _require_mapping(value[content_id], path)
        _require_fields(entity, path, frozenset(("x", "y", "elevation")), frozenset(("x", "y")))
        x = _require_signed_int64(entity["x"], f"{path}.x")
        y = _require_signed_int64(entity["y"], f"{path}.y")
        elevation = 0
        if "elevation" in entity:
            elevation = _require_non_negative_int64(entity["elevation"], f"{path}.elevation")
        entities.append(
            FixtureEntity(
                entity_id,
                WorldPosition(WorldSubunits(x), WorldSubunits(y), ElevationLayer(elevation)),
            )
        )
    return tuple(entities)


def _parse_trigger_ticks(value: object, path: str) -> tuple[int, ...]:
    if not isinstance(value, list):
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_TYPE, path, "fixture value must be an array"
        )
    if len(value) > MAX_FIXTURE_SCHEDULED_TRIGGERS:
        raise _FixtureError(
            FixtureDiagnosticCode.TOO_MANY_ITEMS,
            path,
            "fixture scheduled trigger count exceeds the configured limit",
        )
    return tuple(
        sorted(
            _require_non_negative_int64(item, f"{path}[{index}]")
            for index, item in enumerate(value)
        )
    )


def _require_fields(
    value: dict[str, object],
    path: str,
    allowed: frozenset[str],
    required: frozenset[str] | None = None,
) -> None:
    required_fields = allowed if required is None else required
    unknown = sorted(set(value).difference(allowed))
    if unknown:
        raise _FixtureError(
            FixtureDiagnosticCode.UNKNOWN_FIELD,
            path,
            f"unknown field {unknown[0]!r}",
        )
    missing = sorted(required_fields.difference(value))
    if missing:
        raise _FixtureError(
            FixtureDiagnosticCode.MISSING_FIELD,
            path,
            f"missing required field {missing[0]!r}",
        )


def _require_mapping(value: object, path: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_TYPE, path, "fixture value must be an object"
        )
    return value


def _require_string(value: object, path: str) -> str:
    if not isinstance(value, str):
        raise _FixtureError(FixtureDiagnosticCode.INVALID_TYPE, path, "fixture value must be text")
    return value


def _require_identifier(value: object, path: str) -> str:
    text = _require_string(value, path)
    if not _is_identifier(text):
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_VALUE,
            path,
            "fixture identifier must be a lowercase ASCII identifier",
        )
    return text


def _require_integer(value: object, path: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_TYPE, path, "fixture value must be an integer"
        )
    return value


def _require_signed_int64(value: object, path: str) -> int:
    number = _require_integer(value, path)
    if not -(1 << 63) <= number <= MAX_TICK:
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_VALUE,
            path,
            "fixture value must fit signed 64-bit range",
        )
    return number


def _require_non_negative_int64(value: object, path: str) -> int:
    number = _require_integer(value, path)
    if not 0 <= number <= MAX_TICK:
        raise _FixtureError(
            FixtureDiagnosticCode.INVALID_VALUE,
            path,
            "fixture value must fit non-negative signed 64-bit range",
        )
    return number


def _validate_nesting(value: object, depth: int) -> None:
    if depth > MAX_FIXTURE_NESTING:
        raise _FixtureError(FixtureDiagnosticCode.TOO_DEEP, "$", "fixture nesting exceeds limit")
    if isinstance(value, dict):
        for item in value.values():
            _validate_nesting(item, depth + 1)
    elif isinstance(value, list):
        for item in value:
            _validate_nesting(item, depth + 1)


def _reject_duplicate_fields(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise _DuplicateFieldError(key)
        value[key] = item
    return value


def _failure(
    source: str, code: FixtureDiagnosticCode, path: str, message: str
) -> FixtureLoadFailure:
    return FixtureLoadFailure(source, (FixtureDiagnostic(code, path, message),))


def _is_identifier(value: object) -> bool:
    return (
        isinstance(value, str)
        and bool(value)
        and value.isascii()
        and value.isidentifier()
        and value == value.lower()
    )


@dataclass(frozen=True, slots=True)
class _FixtureError(Exception):
    code: FixtureDiagnosticCode
    path: str
    message: str


@dataclass(frozen=True, slots=True)
class _DuplicateFieldError(Exception):
    field: str
