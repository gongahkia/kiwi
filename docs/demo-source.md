# Demo Source

`docs/v1.0-scene-color-demo.gif` uses the in-tree MIT-licensed cube scene (`share/strok/scenes/cube.obj`). It renders 36 deterministic still snapshots through `--mode luminance --scene-camera orbit`; the scene rasterizer encodes normals as RGB albedo. A local Adwaita Mono font preserves the scene glyphs, and Pango plus FFmpeg add the label and assemble the 3.6-second GIF. It has no external media dependency.

`docs/v1.0-hatch-cat-demo.gif` uses six seconds (01.00–07.00) of Wikimedia Commons' [`Black and white cat drinks from a puddle.ogv`](https://commons.wikimedia.org/wiki/File:Black_and_white_cat_drinks_from_a_puddle.ogv), authored by Mattes and dedicated to the public domain. The right panel contains 24 deterministic snapshots rendered through `--mode structure --style hatch`; FFmpeg and Pango assemble the labelled comparison at four frames per second. The source clip is not stored in this repository.

`docs/v1.0-input-to-structure.gif` and `docs/v1.0-color-tiers.gif` are retained but not shown in the README gallery. They use generated FFmpeg media and have no external dependency.

`docs/v1.0-split-demo.gif` uses generated FFmpeg `testsrc2` footage rendered twice with strok still snapshots, then stacked with `ffmpeg`: luminance on the left, `--mode structure --style hatch` on the right.

`docs/v1.0-scene-demo.gif` uses the in-tree MIT-licensed bundled cube scene (`share/strok/scenes/cube.obj`) rendered with `--style cell-shade --scene-camera orbit`.

`docs/v1.0-shader-demo.gif` uses the in-tree MIT-licensed bundled plasma shader (`share/strok/shaders/plasma.glsl`) rendered with the macOS Metal shader input path and default ASCII renderer.

`docs/v0.5-structure-demo.gif` uses a 2.4s excerpt from Wikimedia Commons `File:Black and white cat drinks from a puddle.ogv`.

- URL: https://commons.wikimedia.org/wiki/File:Black_and_white_cat_drinks_from_a_puddle.ogv
- Source media: https://upload.wikimedia.org/wikipedia/commons/8/8b/Black_and_white_cat_drinks_from_a_puddle.ogv
- License: Public domain (`pd`); attribution not required.
- Artist: User:Mattes.
- Processing: terminal captures recorded with `asciinema`, rendered with `agg`, and stacked with `ffmpeg`.
