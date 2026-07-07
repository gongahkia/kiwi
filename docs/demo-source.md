# Demo Source

`docs/v1.0-split-demo.gif` uses generated FFmpeg `testsrc2` footage rendered twice with contourtty still snapshots, then stacked with `ffmpeg`: luminance on the left, `--mode structure --style hatch` on the right.

`docs/v1.0-scene-demo.gif` uses the in-tree MIT-licensed bundled cube scene (`share/contourtty/scenes/cube.obj`) rendered with `--style cell-shade --scene-camera orbit`.

`docs/v1.0-shader-demo.gif` uses the in-tree MIT-licensed bundled plasma shader (`share/contourtty/shaders/plasma.glsl`) rendered with the macOS Metal shader input path and default ASCII renderer.

`docs/v0.5-structure-demo.gif` uses a 2.4s excerpt from Wikimedia Commons `File:Black and white cat drinks from a puddle.ogv`.

- URL: https://commons.wikimedia.org/wiki/File:Black_and_white_cat_drinks_from_a_puddle.ogv
- Source media: https://upload.wikimedia.org/wikipedia/commons/8/8b/Black_and_white_cat_drinks_from_a_puddle.ogv
- License: Public domain (`pd`); attribution not required.
- Artist: User:Mattes.
- Processing: terminal captures recorded with `asciinema`, rendered with `agg`, and stacked with `ffmpeg`.
