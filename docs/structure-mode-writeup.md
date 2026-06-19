# Structure Mode Technique

Structure mode is the reason contourtty exists: it treats ASCII characters as small stroke shapes, not as square pixels. The renderer still samples brightness, but brightness is only the fallback. The main pass looks for local structure and chooses glyphs that match edge direction and stroke shape.

## Pipeline

```text
decoded RGB frame
  -> luminance field
  -> optional contrast and DoG line isolation
  -> Sobel gradients
  -> per-cell edge magnitude and orientation
  -> optional shape-vector match
  -> CellBuffer
  -> terminal emission or export
```

The decode path owns RGB frames. The renderer converts those frames into a `CellBuffer`, and every output path consumes that buffer. Live terminal playback, ANSI/asciinema export, MP4 raster export, and golden-frame tests therefore exercise the same glyph decisions.

## Baseline Luminance

Luminance mode divides the frame into terminal-sized regions. Each cell region is averaged to an RGB color, converted to relative luminance, then mapped onto a glyph ramp such as:

```text
 .:-=+*#%@
```

This is fast and readable, but it loses orientation. A bright vertical edge and a bright flat area can map to the same glyph even though the terminal has characters that carry direction.

## Directional Edges

Structure mode starts with the same cell average, then builds a luminance field over the source frame. Optional `--contrast` widens local separation. Optional `--dog-sigma N[,M]` applies difference-of-Gaussians filtering to emphasize line-like detail before edge detection.

Sobel gradients provide `gx`, `gy`, magnitude, and orientation. For each terminal cell, contourtty summarizes the source pixels under that cell:

- strong horizontal gradient -> vertical stroke glyphs like `|`
- strong vertical gradient -> horizontal stroke glyphs like `_` or `-`
- diagonal gradients -> `/` or `\`
- mixed strong axes -> `+`
- weak gradients -> keep the luminance glyph

`--edge-threshold` controls the minimum edge magnitude. `--edge-strength` scales how aggressively the overlay appears; `0` disables the overlay.

## Shape Matching

Directional mapping is useful, but a cell may contain more than a single clean edge. Shape matching makes the choice less one-dimensional.

At startup, contourtty precomputes small bitmap-like feature vectors for the structure glyph set:

```text
 |/_\-+
```

For an active edge cell, the renderer samples the edge magnitude field inside that cell into a fixed set of regions: center, cardinal sides, and corners. That sampled shape vector is compared against each glyph vector, and the closest glyph wins.

This favors the character whose ink distribution best matches the edge layout under the cell. It is still lightweight enough for live playback because each cell is independent, so the analysis and render loops can split work by row bands.

## Why Terminal Cell Aspect Matters

Terminal cells are usually taller than they are wide. contourtty defaults `--cell-aspect` to `0.5`, meaning one cell is treated as roughly half as wide as it is tall. Layout uses that correction before sampling; otherwise circles become stretched and edge orientation decisions drift.

The aspect correction is applied before luminance, structure, halfblock, braille, and exports, so the `CellBuffer` dimensions stay consistent across output targets.

## Performance Notes

The expensive work is not one glyph lookup. It is the full structure pass: contrast/DoG, Sobel gradients, region sampling, and per-cell matching. G1 parallelized those row-oriented passes and preserved byte-identical output against the baseline transcript.

Current benchmark evidence in `BENCHMARKS.md` shows the row-band CPU path improved the 4-frame 1280x720 structure benchmark from `36.17s` to `4.35s` wall time while preserving the transcript hash. GPU compute remains optional and useful mainly at high cell counts where readback overhead can be amortized.

## Failure Modes

- Low contrast footage may need `--contrast`.
- Thin details may need DoG enabled with `--dog-sigma`.
- Dense truecolor output can be slower than mono because terminal bytes dominate.
- Palette dithering can improve 16/256-color output but adds CPU work.
- Webcam capture still depends on platform device behavior and remains separately tracked.
