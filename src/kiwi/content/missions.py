"""Strict versioned renderer-independent mission-content loading."""

from __future__ import annotations

import json
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Protocol, cast

from kiwi.domain.geometry import ElevationLayer, WorldPosition, WorldRectangle, WorldSubunits

MISSION_FORMAT = "kiwi-mission"
MISSION_VERSION = 1
MAX_MISSION_BYTES = 1_048_576
MAX_MISSION_NESTING = 16
MAX_MISSION_OBSTACLES = 64
MAX_MISSION_COVERS = 64
MAX_MISSION_REGIONS = 32
MAX_MISSION_COVER_SLOTS = 16
MAX_MISSION_TEXT_LENGTH = 256
MAX_UINT64 = (1 << 64) - 1
MAX_COVER_INTEGRITY_BASIS_POINTS = 10_000


class MissionDiagnosticCode(StrEnum):
    """Stable mission-content loader and validation diagnostic codes."""

    READ_FAILED = "M001_READ_FAILED"
    TOO_LARGE = "M002_TOO_LARGE"
    INVALID_UTF8 = "M003_INVALID_UTF8"
    INVALID_JSON = "M004_INVALID_JSON"
    DUPLICATE_FIELD = "M005_DUPLICATE_FIELD"
    TOO_DEEP = "M006_TOO_DEEP"
    TOP_LEVEL_TYPE = "M007_TOP_LEVEL_TYPE"
    UNKNOWN_FIELD = "M008_UNKNOWN_FIELD"
    MISSING_FIELD = "M009_MISSING_FIELD"
    INVALID_TYPE = "M010_INVALID_TYPE"
    INVALID_VALUE = "M011_INVALID_VALUE"
    UNSUPPORTED_VERSION = "M012_UNSUPPORTED_VERSION"
    TOO_MANY_ITEMS = "M013_TOO_MANY_ITEMS"
    DUPLICATE_ID = "M014_DUPLICATE_ID"


class MissionCoverSide(StrEnum):
    """One content-level side of a canonically directed cover segment."""

    LEFT = "left"
    RIGHT = "right"


class MissionCoverHeight(StrEnum):
    """One content-level cover protection-height class."""

    LOW = "low"
    HIGH = "high"


@dataclass(frozen=True, slots=True)
class MissionDiagnostic:
    """One stable validation diagnostic with a JSON-path provenance location."""

    code: MissionDiagnosticCode
    path: str
    message: str


@dataclass(frozen=True, slots=True)
class MissionLoadFailure:
    """The structured failure returned for untrusted mission content."""

    source: str
    diagnostics: tuple[MissionDiagnostic, ...]

    def __post_init__(self) -> None:
        if not isinstance(self.source, str):
            raise ValueError("mission failure source must be text")
        if not isinstance(self.diagnostics, tuple) or not self.diagnostics:
            raise ValueError("mission failure requires immutable diagnostics")


@dataclass(frozen=True, slots=True)
class MissionObstacle:
    """One content-ID-keyed immutable obstacle before authority IDs are allocated."""

    content_id: str
    bounds: WorldRectangle
    elevation: ElevationLayer

    def __post_init__(self) -> None:
        if not _is_identifier(self.content_id):
            raise ValueError("mission obstacle ID must be a lowercase ASCII identifier")
        if not isinstance(self.bounds, WorldRectangle):
            raise ValueError("mission obstacle requires bounds")
        if not isinstance(self.elevation, ElevationLayer):
            raise ValueError("mission obstacle requires an elevation layer")


@dataclass(frozen=True, slots=True)
class MissionCoverSlot:
    """One content-defined standing location before a cover slot index is allocated."""

    position: WorldPosition
    side: MissionCoverSide

    def __post_init__(self) -> None:
        if not isinstance(self.position, WorldPosition):
            raise ValueError("mission cover slot requires a position")
        if not isinstance(self.side, MissionCoverSide):
            raise ValueError("mission cover slot requires a cover side")


@dataclass(frozen=True, slots=True)
class MissionCover:
    """One content-ID-keyed cover edge before authority IDs are allocated."""

    content_id: str
    start: WorldPosition
    end: WorldPosition
    height: MissionCoverHeight
    integrity_basis_points: int
    slots: tuple[MissionCoverSlot, ...]

    def __post_init__(self) -> None:
        if not _is_identifier(self.content_id):
            raise ValueError("mission cover ID must be a lowercase ASCII identifier")
        if not isinstance(self.start, WorldPosition) or not isinstance(self.end, WorldPosition):
            raise ValueError("mission cover endpoints must be positions")
        if self.start.elevation != self.end.elevation:
            raise ValueError("mission cover endpoints must share an elevation")
        if _position_key(self.start) >= _position_key(self.end):
            raise ValueError("mission cover endpoints must be canonically ordered")
        if not isinstance(self.height, MissionCoverHeight):
            raise ValueError("mission cover requires a height")
        if (
            not isinstance(self.integrity_basis_points, int)
            or isinstance(self.integrity_basis_points, bool)
            or not 0 <= self.integrity_basis_points <= MAX_COVER_INTEGRITY_BASIS_POINTS
        ):
            raise ValueError("mission cover integrity must be between zero and 10,000")
        if not isinstance(self.slots, tuple) or not 1 <= len(self.slots) <= MAX_MISSION_COVER_SLOTS:
            raise ValueError("mission cover requires one through 16 immutable slots")
        previous_key: tuple[int, int, int, str] | None = None
        for slot in self.slots:
            if not isinstance(slot, MissionCoverSlot):
                raise ValueError("mission cover slots must contain mission cover slots")
            if slot.position.elevation != self.start.elevation:
                raise ValueError("mission cover slots must share the cover elevation")
            key = (*_position_key(slot.position), slot.side.value)
            if previous_key is not None and key <= previous_key:
                raise ValueError("mission cover slots must be canonically ordered and unique")
            previous_key = key


@dataclass(frozen=True, slots=True)
class MissionRegion:
    """One content-ID-keyed named tactical area."""

    content_id: str
    bounds: WorldRectangle

    def __post_init__(self) -> None:
        if not _is_identifier(self.content_id):
            raise ValueError("mission region ID must be a lowercase ASCII identifier")
        if not isinstance(self.bounds, WorldRectangle):
            raise ValueError("mission region requires bounds")


class _ContentRecord(Protocol):
    @property
    def content_id(self) -> str: ...


@dataclass(frozen=True, slots=True)
class MissionData:
    """One normalised, versioned, renderer-independent tactical mission definition."""

    mission_id: str
    title: str
    tick_rate: int
    seed: int
    map_bounds: WorldRectangle
    obstacles: tuple[MissionObstacle, ...]
    covers: tuple[MissionCover, ...]
    regions: tuple[MissionRegion, ...]

    def __post_init__(self) -> None:
        if not _is_identifier(self.mission_id):
            raise ValueError("mission ID must be a lowercase ASCII identifier")
        if not _is_text(self.title):
            raise ValueError("mission title must be bounded non-empty text")
        if not isinstance(self.tick_rate, int) or isinstance(self.tick_rate, bool):
            raise ValueError("mission tick rate must be an integer")
        if self.tick_rate not in (20, 30, 60):
            raise ValueError("mission tick rate must be 20, 30, or 60")
        if (
            not isinstance(self.seed, int)
            or isinstance(self.seed, bool)
            or not 0 <= self.seed <= MAX_UINT64
        ):
            raise ValueError("mission seed must fit the unsigned 64-bit range")
        if not isinstance(self.map_bounds, WorldRectangle):
            raise ValueError("mission requires map bounds")
        _require_canonical_records(self.obstacles, MissionObstacle, "mission obstacles")
        _require_canonical_records(self.covers, MissionCover, "mission covers")
        _require_canonical_records(self.regions, MissionRegion, "mission regions")
        for obstacle in self.obstacles:
            if not self.map_bounds.contains_rectangle(obstacle.bounds):
                raise ValueError("mission obstacles must lie within map bounds")
        for cover in self.covers:
            if not self.map_bounds.contains_position(
                cover.start
            ) or not self.map_bounds.contains_position(cover.end):
                raise ValueError("mission cover endpoints must lie within map bounds")
            for slot in cover.slots:
                if not self.map_bounds.contains_position(slot.position):
                    raise ValueError("mission cover slots must lie within map bounds")
        for region in self.regions:
            if not self.map_bounds.contains_rectangle(region.bounds):
                raise ValueError("mission regions must lie within map bounds")

    def region_for(self, content_id: str) -> MissionRegion | None:
        """Return one named region without exposing unordered lookup semantics."""
        if not isinstance(content_id, str):
            raise TypeError("mission region ID must be text")
        for region in self.regions:
            if region.content_id == content_id:
                return region
        return None


type MissionLoadResult = MissionData | MissionLoadFailure


def load_mission_file(path: Path) -> MissionLoadResult:
    """Read and validate one bounded UTF-8 mission file."""
    if not isinstance(path, Path):
        raise TypeError("mission path must be a Path")
    try:
        data = path.read_bytes()
    except OSError:
        return _failure(str(path), MissionDiagnosticCode.READ_FAILED, "$", "could not read mission")
    return load_mission_bytes(data, str(path))


def load_mission_bytes(data: bytes, source: str = "<bytes>") -> MissionLoadResult:
    """Validate one bounded mission document without importing pygame."""
    if not isinstance(data, bytes):
        raise TypeError("mission data must be bytes")
    if not isinstance(source, str):
        raise TypeError("mission source must be text")
    if len(data) > MAX_MISSION_BYTES:
        return _failure(
            source, MissionDiagnosticCode.TOO_LARGE, "$", "mission exceeds the byte limit"
        )
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return _failure(
            source, MissionDiagnosticCode.INVALID_UTF8, "$", "mission is not valid UTF-8"
        )
    try:
        document = json.loads(text, object_pairs_hook=_reject_duplicate_fields)
    except json.JSONDecodeError:
        return _failure(
            source, MissionDiagnosticCode.INVALID_JSON, "$", "mission is not valid JSON"
        )
    except _DuplicateFieldError as error:
        return _failure(
            source,
            MissionDiagnosticCode.DUPLICATE_FIELD,
            "$",
            f"duplicate JSON object field {error.field!r}",
        )
    except RecursionError:
        return _failure(
            source, MissionDiagnosticCode.TOO_DEEP, "$", "mission nesting exceeds limit"
        )
    try:
        _validate_nesting(document, 0)
        return _parse_mission(document)
    except _MissionError as error:
        return _failure(source, error.code, error.path, error.message)


def _parse_mission(document: object) -> MissionData:
    root = _require_mapping(document, "$")
    _require_fields(
        root,
        "$",
        frozenset(
            ("format", "version", "id", "title", "tick_rate", "seed", "map", "covers", "regions")
        ),
    )
    format_name = _require_string(root["format"], "$.format")
    if format_name != MISSION_FORMAT:
        raise _MissionError(
            MissionDiagnosticCode.INVALID_VALUE, "$.format", "mission format is invalid"
        )
    version = _require_integer(root["version"], "$.version")
    if version != MISSION_VERSION:
        raise _MissionError(
            MissionDiagnosticCode.UNSUPPORTED_VERSION,
            "$.version",
            f"unsupported mission version {version}",
        )
    mission_id = _require_identifier(root["id"], "$.id")
    title = _require_text(root["title"], "$.title")
    tick_rate = _require_integer(root["tick_rate"], "$.tick_rate")
    if tick_rate not in (20, 30, 60):
        raise _MissionError(
            MissionDiagnosticCode.INVALID_VALUE,
            "$.tick_rate",
            "mission tick rate must be 20, 30, or 60",
        )
    seed = _require_integer(root["seed"], "$.seed")
    if not 0 <= seed <= MAX_UINT64:
        raise _MissionError(
            MissionDiagnosticCode.INVALID_VALUE,
            "$.seed",
            "mission seed must fit the unsigned 64-bit range",
        )
    bounds, obstacles = _parse_map(root["map"], "$.map")
    covers = _parse_covers(root["covers"], "$.covers")
    regions = _parse_regions(root["regions"], "$.regions")
    try:
        return MissionData(mission_id, title, tick_rate, seed, bounds, obstacles, covers, regions)
    except ValueError as error:
        raise _MissionError(MissionDiagnosticCode.INVALID_VALUE, "$", str(error)) from error


def _parse_map(value: object, path: str) -> tuple[WorldRectangle, tuple[MissionObstacle, ...]]:
    mapping = _require_mapping(value, path)
    _require_fields(mapping, path, frozenset(("bounds", "obstacles")))
    bounds = _parse_rectangle(mapping["bounds"], f"{path}.bounds")
    obstacles_value = _require_list(mapping["obstacles"], f"{path}.obstacles")
    if len(obstacles_value) > MAX_MISSION_OBSTACLES:
        raise _MissionError(
            MissionDiagnosticCode.TOO_MANY_ITEMS,
            f"{path}.obstacles",
            "mission obstacle count exceeds the configured limit",
        )
    obstacles: list[MissionObstacle] = []
    for index, item in enumerate(obstacles_value):
        item_path = f"{path}.obstacles[{index}]"
        mapping = _require_mapping(item, item_path)
        _require_fields(mapping, item_path, frozenset(("id", "bounds", "elevation")))
        obstacles.append(
            MissionObstacle(
                _require_identifier(mapping["id"], f"{item_path}.id"),
                _parse_rectangle(mapping["bounds"], f"{item_path}.bounds"),
                _parse_elevation(mapping["elevation"], f"{item_path}.elevation"),
            )
        )
    return bounds, _sorted_unique_records(obstacles, f"{path}.obstacles")


def _parse_covers(value: object, path: str) -> tuple[MissionCover, ...]:
    items = _require_list(value, path)
    if len(items) > MAX_MISSION_COVERS:
        raise _MissionError(
            MissionDiagnosticCode.TOO_MANY_ITEMS,
            path,
            "mission cover count exceeds the configured limit",
        )
    covers: list[MissionCover] = []
    for index, item in enumerate(items):
        item_path = f"{path}[{index}]"
        mapping = _require_mapping(item, item_path)
        _require_fields(
            mapping,
            item_path,
            frozenset(("id", "start", "end", "height", "integrity", "slots")),
        )
        start = _parse_position(mapping["start"], f"{item_path}.start")
        end = _parse_position(mapping["end"], f"{item_path}.end")
        if start.elevation != end.elevation:
            raise _MissionError(
                MissionDiagnosticCode.INVALID_VALUE,
                f"{item_path}.end.elevation",
                "mission cover endpoints must share an elevation",
            )
        if _position_key(start) >= _position_key(end):
            raise _MissionError(
                MissionDiagnosticCode.INVALID_VALUE,
                f"{item_path}.end",
                "mission cover endpoints must be canonically ordered",
            )
        height_value = _require_string(mapping["height"], f"{item_path}.height")
        try:
            height = MissionCoverHeight(height_value)
        except ValueError as error:
            raise _MissionError(
                MissionDiagnosticCode.INVALID_VALUE,
                f"{item_path}.height",
                "mission cover height must be low or high",
            ) from error
        integrity_basis_points = _require_integer(mapping["integrity"], f"{item_path}.integrity")
        if not 0 <= integrity_basis_points <= MAX_COVER_INTEGRITY_BASIS_POINTS:
            raise _MissionError(
                MissionDiagnosticCode.INVALID_VALUE,
                f"{item_path}.integrity",
                "mission cover integrity must be between zero and 10,000",
            )
        slots = _parse_cover_slots(mapping["slots"], f"{item_path}.slots", start.elevation)
        covers.append(
            MissionCover(
                _require_identifier(mapping["id"], f"{item_path}.id"),
                start,
                end,
                height,
                integrity_basis_points,
                slots,
            )
        )
    return _sorted_unique_records(covers, path)


def _parse_cover_slots(
    value: object, path: str, elevation: ElevationLayer
) -> tuple[MissionCoverSlot, ...]:
    items = _require_list(value, path)
    if not items:
        raise _MissionError(
            MissionDiagnosticCode.INVALID_VALUE, path, "mission cover requires a slot"
        )
    if len(items) > MAX_MISSION_COVER_SLOTS:
        raise _MissionError(
            MissionDiagnosticCode.TOO_MANY_ITEMS,
            path,
            "mission cover slot count exceeds the configured limit",
        )
    slots: list[MissionCoverSlot] = []
    for index, item in enumerate(items):
        item_path = f"{path}[{index}]"
        mapping = _require_mapping(item, item_path)
        _require_fields(mapping, item_path, frozenset(("x", "y", "side")))
        side_value = _require_string(mapping["side"], f"{item_path}.side")
        try:
            side = MissionCoverSide(side_value)
        except ValueError as error:
            raise _MissionError(
                MissionDiagnosticCode.INVALID_VALUE,
                f"{item_path}.side",
                "mission cover side must be left or right",
            ) from error
        slots.append(
            MissionCoverSlot(
                _position_from_components(
                    _require_integer(mapping["x"], f"{item_path}.x"),
                    _require_integer(mapping["y"], f"{item_path}.y"),
                    elevation,
                    item_path,
                ),
                side,
            )
        )
    slots.sort(key=lambda slot: (*_position_key(slot.position), slot.side.value))
    for index in range(len(slots) - 1):
        previous = slots[index]
        current = slots[index + 1]
        if previous.position == current.position:
            raise _MissionError(
                MissionDiagnosticCode.INVALID_VALUE,
                path,
                "mission cover slots must have unique positions",
            )
    return tuple(slots)


def _parse_regions(value: object, path: str) -> tuple[MissionRegion, ...]:
    items = _require_list(value, path)
    if len(items) > MAX_MISSION_REGIONS:
        raise _MissionError(
            MissionDiagnosticCode.TOO_MANY_ITEMS,
            path,
            "mission region count exceeds the configured limit",
        )
    regions: list[MissionRegion] = []
    for index, item in enumerate(items):
        item_path = f"{path}[{index}]"
        mapping = _require_mapping(item, item_path)
        _require_fields(mapping, item_path, frozenset(("id", "bounds")))
        regions.append(
            MissionRegion(
                _require_identifier(mapping["id"], f"{item_path}.id"),
                _parse_rectangle(mapping["bounds"], f"{item_path}.bounds"),
            )
        )
    return _sorted_unique_records(regions, path)


def _parse_rectangle(value: object, path: str) -> WorldRectangle:
    mapping = _require_mapping(value, path)
    _require_fields(
        mapping,
        path,
        frozenset(("minimum_x", "minimum_y", "maximum_x", "maximum_y")),
    )
    try:
        return WorldRectangle(
            WorldSubunits(_require_integer(mapping["minimum_x"], f"{path}.minimum_x")),
            WorldSubunits(_require_integer(mapping["minimum_y"], f"{path}.minimum_y")),
            WorldSubunits(_require_integer(mapping["maximum_x"], f"{path}.maximum_x")),
            WorldSubunits(_require_integer(mapping["maximum_y"], f"{path}.maximum_y")),
        )
    except ValueError as error:
        raise _MissionError(MissionDiagnosticCode.INVALID_VALUE, path, str(error)) from error


def _parse_position(value: object, path: str) -> WorldPosition:
    mapping = _require_mapping(value, path)
    _require_fields(mapping, path, frozenset(("x", "y", "elevation")))
    return _position_from_components(
        _require_integer(mapping["x"], f"{path}.x"),
        _require_integer(mapping["y"], f"{path}.y"),
        _parse_elevation(mapping["elevation"], f"{path}.elevation"),
        path,
    )


def _position_from_components(
    x: int, y: int, elevation: ElevationLayer, path: str
) -> WorldPosition:
    try:
        return WorldPosition(WorldSubunits(x), WorldSubunits(y), elevation)
    except ValueError as error:
        raise _MissionError(MissionDiagnosticCode.INVALID_VALUE, path, str(error)) from error


def _parse_elevation(value: object, path: str) -> ElevationLayer:
    try:
        return ElevationLayer(_require_integer(value, path))
    except ValueError as error:
        raise _MissionError(MissionDiagnosticCode.INVALID_VALUE, path, str(error)) from error


def _require_canonical_records(values: object, expected_type: type[object], name: str) -> None:
    if not isinstance(values, tuple):
        raise ValueError(f"{name} must be an immutable tuple")
    previous_id = ""
    for value in values:
        if not isinstance(value, expected_type):
            raise ValueError(f"{name} must contain {expected_type.__name__} values")
        content_id = cast(_ContentRecord, value).content_id
        if content_id <= previous_id:
            raise ValueError(f"{name} must use unique canonical content IDs")
        previous_id = content_id


def _sorted_unique_records[RecordT: _ContentRecord](
    records: list[RecordT], path: str
) -> tuple[RecordT, ...]:
    records.sort(key=lambda record: record.content_id)
    for index in range(len(records) - 1):
        previous = records[index]
        current = records[index + 1]
        if previous.content_id == current.content_id:
            raise _MissionError(
                MissionDiagnosticCode.DUPLICATE_ID,
                path,
                f"duplicate mission content ID {current.content_id!r}",
            )
    return tuple(records)


def _require_fields(value: dict[str, object], path: str, allowed: frozenset[str]) -> None:
    unknown = sorted(set(value).difference(allowed))
    if unknown:
        raise _MissionError(
            MissionDiagnosticCode.UNKNOWN_FIELD,
            path,
            f"unknown field {unknown[0]!r}",
        )
    missing = sorted(allowed.difference(value))
    if missing:
        raise _MissionError(
            MissionDiagnosticCode.MISSING_FIELD,
            path,
            f"missing required field {missing[0]!r}",
        )


def _require_mapping(value: object, path: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise _MissionError(
            MissionDiagnosticCode.INVALID_TYPE, path, "mission value must be an object"
        )
    return value


def _require_list(value: object, path: str) -> list[object]:
    if not isinstance(value, list):
        raise _MissionError(
            MissionDiagnosticCode.INVALID_TYPE, path, "mission value must be an array"
        )
    return value


def _require_string(value: object, path: str) -> str:
    if not isinstance(value, str):
        raise _MissionError(MissionDiagnosticCode.INVALID_TYPE, path, "mission value must be text")
    return value


def _require_text(value: object, path: str) -> str:
    text = _require_string(value, path)
    if not _is_text(text):
        raise _MissionError(
            MissionDiagnosticCode.INVALID_VALUE,
            path,
            "mission text must be non-empty ASCII text within the configured limit",
        )
    return text


def _require_identifier(value: object, path: str) -> str:
    identifier = _require_string(value, path)
    if not _is_identifier(identifier):
        raise _MissionError(
            MissionDiagnosticCode.INVALID_VALUE,
            path,
            "mission ID must be a lowercase ASCII identifier",
        )
    return identifier


def _require_integer(value: object, path: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise _MissionError(
            MissionDiagnosticCode.INVALID_TYPE, path, "mission value must be an integer"
        )
    return value


def _is_identifier(value: str) -> bool:
    return (
        isinstance(value, str)
        and 1 <= len(value) <= MAX_MISSION_TEXT_LENGTH
        and value.isascii()
        and value.isidentifier()
        and value == value.lower()
    )


def _is_text(value: str) -> bool:
    return (
        isinstance(value, str)
        and 1 <= len(value) <= MAX_MISSION_TEXT_LENGTH
        and value.isascii()
        and "\n" not in value
        and "\r" not in value
    )


def _position_key(position: WorldPosition) -> tuple[int, int, int]:
    return (position.x.value, position.y.value, position.elevation.value)


def _validate_nesting(value: object, depth: int) -> None:
    if depth > MAX_MISSION_NESTING:
        raise _MissionError(MissionDiagnosticCode.TOO_DEEP, "$", "mission nesting exceeds limit")
    if isinstance(value, dict):
        for child in value.values():
            _validate_nesting(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            _validate_nesting(child, depth + 1)


def _failure(
    source: str, code: MissionDiagnosticCode, path: str, message: str
) -> MissionLoadFailure:
    return MissionLoadFailure(source, (MissionDiagnostic(code, path, message),))


class _MissionError(Exception):
    def __init__(self, code: MissionDiagnosticCode, path: str, message: str) -> None:
        self.code = code
        self.path = path
        self.message = message


class _DuplicateFieldError(Exception):
    def __init__(self, field: str) -> None:
        self.field = field


def _reject_duplicate_fields(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for field, value in pairs:
        if field in result:
            raise _DuplicateFieldError(field)
        result[field] = value
    return result
