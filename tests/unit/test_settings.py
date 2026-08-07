from __future__ import annotations

from pathlib import Path

from kiwi.app.settings import (
    SettingsLoadFailureCode,
    UiSettings,
    decode_ui_settings,
    encode_ui_settings,
    load_ui_settings,
    save_ui_settings,
)


def test_ui_settings_round_trip_and_render_scale() -> None:
    settings = UiSettings(2, 3)

    decoded = decode_ui_settings(encode_ui_settings(settings))

    assert decoded.settings == settings
    assert decoded.failure is None
    assert settings.render_scale == 6
    assert settings.font_pixel_height == 72


def test_invalid_or_missing_settings_safely_use_defaults(tmp_path: Path) -> None:
    invalid = decode_ui_settings(b"{")
    missing = load_ui_settings(tmp_path / "missing.json")

    assert invalid.settings == UiSettings()
    assert invalid.failure is not None
    assert invalid.failure.code is SettingsLoadFailureCode.INVALID_JSON
    assert missing.settings == UiSettings()
    assert missing.failure is not None
    assert missing.failure.code is SettingsLoadFailureCode.READ_FAILED


def test_settings_save_writes_canonical_json(tmp_path: Path) -> None:
    path = tmp_path / "settings.json"

    save_ui_settings(path, UiSettings(3, 2))

    assert load_ui_settings(path).settings == UiSettings(3, 2)


def test_corrupt_settings_recover_from_the_last_complete_backup(tmp_path: Path) -> None:
    path = tmp_path / "settings.json"
    first = UiSettings(2, 1)

    assert save_ui_settings(path, first).failure is None
    assert save_ui_settings(path, UiSettings(3, 1)).failure is None
    path.write_text("{", encoding="utf-8")

    recovered = load_ui_settings(path)

    assert recovered.settings == first
    assert recovered.failure is not None
    assert recovered.failure.code is SettingsLoadFailureCode.INVALID_JSON
    assert recovered.recovered_from_backup
    assert load_ui_settings(path).settings == first


def test_v1_settings_migrate_to_default_crt_preferences() -> None:
    decoded = decode_ui_settings(
        b'{"font_scale":2,"format":"kiwi-settings","ui_scale":3,"version":1}'
    )

    assert decoded.settings == UiSettings(3, 2, True, False)
    assert decoded.failure is None
