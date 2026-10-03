# Demo Source

`docs/v1.0-input-to-structure.gif` uses generated FFmpeg `testsrc2` footage. The left panel is the source frame; the right panel is strok's truecolor `--mode structure` export. Pango-rendered labels and FFmpeg compose the panels. It has no external media dependency.

`docs/v1.0-color-tiers.gif` uses an animated FFmpeg RGB gradient rendered with strok's luminance mode in truecolor, 256-color, and 16-color configurations. The render command unsets `NO_COLOR`, which otherwise intentionally forces mono output. Pango-rendered labels and FFmpeg compose the panels. It has no external media dependency.

`docs/v1.0-split-demo.gif` uses generated FFmpeg `testsrc2` footage rendered twice with strok still snapshots, then stacked with `ffmpeg`: luminance on the left, `--mode structure --style hatch` on the right.

`docs/v1.0-scene-demo.gif` uses the in-tree MIT-licensed bundled cube scene (`share/strok/scenes/cube.obj`) rendered with `--style cell-shade --scene-camera orbit`.

`docs/v1.0-shader-demo.gif` uses the in-tree MIT-licensed bundled plasma shader (`share/strok/shaders/plasma.glsl`) rendered with the macOS Metal shader input path and default ASCII renderer.

`docs/v0.5-structure-demo.gif` uses a 2.4s excerpt from Wikimedia Commons `File:Black and white cat drinks from a puddle.ogv`.

- URL: https://commons.wikimedia.org/wiki/File:Black_and_white_cat_drinks_from_a_puddle.ogv
- Source media: https://upload.wikimedia.org/wikipedia/commons/8/8b/Black_and_white_cat_drinks_from_a_puddle.ogv
- License: Public domain (`pd`); attribution not required.
- Artist: User:Mattes.
- Processing: terminal captures recorded with `asciinema`, rendered with `agg`, and stacked with `ffmpeg`.
