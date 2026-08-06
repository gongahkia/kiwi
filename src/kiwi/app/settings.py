"""Non-authoritative, versioned UI-scale and font-scale settings."""

from __future__ import annotations

import json
from dataclasses import dataclass, replace
from enum import StrEnum
from pathlib import Path

SETTINGS_FORMAT = "kiwi-settings"
SETTINGS_VERSION = 2
MAX_SETTINGS_BYTES = 65_536
MIN_UI_SCALE = 1
MAX_UI_SCALE = 4
MIN_FONT_SCALE = 1
MAX_FONT_SCALE = 3


class SettingsLoadFailureCode(StrEnum):
    READ_FAILED = "ST001_READ_FAILED"
    TOO_LARGE = "ST002_TOO_LARGE"
    INVALID_UTF8 = "ST003_INVALID_UTF8"
    INVALID_JSON = "ST004_INVALID_JSON"
    INVALID_STRUCTURE = "ST005_INVALID_STRUCTURE"


@dataclass(frozen=True, slots=True)
class UiSettings:
    ui_scale: int = 1
    font_scale: int = 1
    crt_enabled: bool = True
    reduced_flicker: bool = False

    def __post_init__(self) -> None:
        _scale(self.ui_scale, MIN_UI_SCALE, MAX_UI_SCALE, "UI")
        _scale(self.font_scale, MIN_FONT_SCALE, MAX_FONT_SCALE, "font")
        if not isinstance(self.crt_enabled, bool) or not isinstance(self.reduced_flicker, bool):
            raise TypeError("CRT settings must be boolean")

    @property
    def render_scale(self) -> int:
        """Return the integer bitmap scale passed to presentation renderers."""
        return self.ui_scale * self.font_scale

    @property
    def font_pixel_height(self) -> int:
        """Return the effective 12-pixel bitmap font height."""
        return 12 * self.render_scale

    def with_ui_scale(self, scale: int) -> UiSettings:
        """Return settings with one validated UI scale."""
        return replace(self, ui_scale=scale)

    def with_font_scale(self, scale: int) -> UiSettings:
        """Return settings with one validated font scale."""
        return replace(self, font_scale=scale)

    def with_crt_enabled(self, enabled: bool) -> UiSettings:
        """Return one presentation-only CRT setting change."""
        if not isinstance(enabled, bool):
            raise TypeError("CRT enabled setting must be boolean")
        return replace(self, crt_enabled=enabled)

    def with_reduced_flicker(self, enabled: bool) -> UiSettings:
        """Return one presentation-only flicker accessibility setting change."""
        if not isinstance(enabled, bool):
            raise TypeError("reduced flicker setting must be boolean")
        return replace(self, reduced_flicker=enabled)


@dataclass(frozen=True, slots=True)
class SettingsLoadFailure:
    code: SettingsLoadFailureCode
    message: str

    def __post_init__(self) -> None:
        if not isinstance(self.code, SettingsLoadFailureCode):
            raise TypeError("settings load failure requires a code")
        if not isinstance(self.message, str) or not self.message:
            raise ValueError("settings load failure requires a message")


@dataclass(frozen=True, slots=True)
class SettingsLoadResult:
    settings: UiSettings
    failure: SettingsLoadFailure | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.settings, UiSettings):
            raise TypeError("settings load result requires UI settings")
        if self.failure is not None and not isinstance(self.failure, SettingsLoadFailure):
            raise TypeError("settings load result failure is invalid")


def encode_ui_settings(settings: UiSettings) -> bytes:
    """Encode settings as canonical UTF-8 JSON without authority data."""
    if not isinstance(settings, UiSettings):
        raise TypeError("settings encoding requires UI settings")
    return json.dumps(
        {
            "crt_enabled": settings.crt_enabled,
            "font_scale": settings.font_scale,
            "format": SETTINGS_FORMAT,
            "reduced_flicker": settings.reduced_flicker,
            "ui_scale": settings.ui_scale,
            "version": SETTINGS_VERSION,
        },
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def decode_ui_settings(data: bytes) -> SettingsLoadResult:
    """Decode settings or return safe defaults with a structured failure."""
    if not isinstance(data, bytes):
        raise TypeError("settings decoding requires bytes")
    if len(data) > MAX_SETTINGS_BYTES:
        return _failed(SettingsLoadFailureCode.TOO_LARGE, "settings exceed the byte limit")
    try:
        value = json.loads(data.decode("utf-8"))
    except UnicodeDecodeError:
        return _failed(SettingsLoadFailureCode.INVALID_UTF8, "settings are not valid UTF-8")
    except json.JSONDecodeError:
        return _failed(SettingsLoadFailureCode.INVALID_JSON, "settings are not valid JSON")
    if not isinstance(value, dict):
        return _failed(SettingsLoadFailureCode.INVALID_STRUCTURE, "settings fields are invalid")
    if value.get("format") != SETTINGS_FORMAT:
        return _failed(SettingsLoadFailureCode.INVALID_STRUCTURE, "settings format is unsupported")
    if value.get("version") == 1 and set(value) == {"font_scale", "format", "ui_scale", "version"}:
        try:
            return SettingsLoadResult(UiSettings(value["ui_scale"], value["font_scale"]))
        except (TypeError, ValueError):
            return _failed(
                SettingsLoadFailureCode.INVALID_STRUCTURE, "settings scale values are invalid"
            )
    if value.get("version") != SETTINGS_VERSION or set(value) != {
        "crt_enabled",
        "font_scale",
        "format",
        "reduced_flicker",
        "ui_scale",
        "version",
    }:
        return _failed(SettingsLoadFailureCode.INVALID_STRUCTURE, "settings fields are invalid")
    try:
        settings = UiSettings(
            value["ui_scale"],
            value["font_scale"],
            value["crt_enabled"],
            value["reduced_flicker"],
        )
    except (TypeError, ValueError):
        return _failed(
            SettingsLoadFailureCode.INVALID_STRUCTURE, "settings scale values are invalid"
        )
    return SettingsLoadResult(settings)


def load_ui_settings(path: Path) -> SettingsLoadResult:
    """Load one bounded settings file, safely falling back to defaults."""
    if not isinstance(path, Path):
        raise TypeError("settings path must be a Path")
    try:
        data = path.read_bytes()
    except OSError:
        return _failed(SettingsLoadFailureCode.READ_FAILED, "settings could not be read")
    return decode_ui_settings(data)


def save_ui_settings(path: Path, settings: UiSettings) -> None:
    """Write one canonical settings file at the application IO boundary."""
    if not isinstance(path, Path):
        raise TypeError("settings path must be a Path")
    path.write_bytes(encode_ui_settings(settings))


def _failed(code: SettingsLoadFailureCode, message: str) -> SettingsLoadResult:
    return SettingsLoadResult(UiSettings(), SettingsLoadFailure(code, message))


def _scale(value: int, minimum: int, maximum: int, label: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or not minimum <= value <= maximum:
        raise ValueError(f"{label} scale must be an integer from {minimum} through {maximum}")
