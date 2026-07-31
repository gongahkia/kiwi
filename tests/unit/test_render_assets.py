from __future__ import annotations

import json
from hashlib import sha256
from pathlib import Path

from kiwi.render.bitmap_font import BIGBLUETERM_FONT_FILENAME

ASSET_DIRECTORY = Path(__file__).resolve().parents[2] / "src" / "kiwi" / "render" / "assets"


def test_bigblueterm_asset_manifest_retains_verified_provenance() -> None:
    manifest = json.loads((ASSET_DIRECTORY / "manifest.json").read_text(encoding="utf-8"))
    asset = manifest["assets"][0]
    font_path = ASSET_DIRECTORY / BIGBLUETERM_FONT_FILENAME

    assert manifest["format"] == "kiwi-render-assets"
    assert manifest["version"] == 1
    assert asset == {
        "attribution": "BigBlue Terminal by VileR (c) 2015; Nerd Fonts patch release v3.4.0",
        "license_file": "BIGBLUETERM-LICENSE.txt",
        "license_spdx": "CC-BY-SA-4.0",
        "path": BIGBLUETERM_FONT_FILENAME,
        "sha256": sha256(font_path.read_bytes()).hexdigest(),
        "source_release": "v3.4.0",
        "source_url": "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/BigBlueTerminal.tar.xz",
    }
    assert "Creative Commons Attribution-ShareAlike 4.0" in (
        ASSET_DIRECTORY / asset["license_file"]
    ).read_text(encoding="utf-8")
