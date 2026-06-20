# PHASE_J.md — Blitter Ladder & Unicode 16 Glyphs

**Goal:** Add octant (2×4 colored sub-cell) and sextant (2×3) blitters, detect terminal + font capabilities at startup, and resolve `--mode auto` against an ordered ladder. Halfblock and braille become rungs on that ladder; structure mode becomes a *contour overlay* on top of whichever rung is active.

**Exit criteria:** `--mode auto` on a current Kitty/WezTerm/Ghostty terminal picks octant; on a Unicode-13 terminal without octant fonts picks sextant; on legacy terminals picks halfblock; documented and tested. `--mode {pixel|octant|sextant|braille|halfblock|structure|luminance}` forces a rung. Octant mode passes the circle test and is visibly higher-resolution than halfblock at the same cell grid.

---

## Architecture decisions locked in this phase

- **A blitter is a Pass that produces both `CellGlyphs` and `CellColors`.** It supersedes the per-mode special cases currently in `renderFrame()`. Slots into Phase H's graph.
- **Capability detection is best-effort at startup, never blocking.** No DA1/DA2 escapes that can hang on serial transports; environment variables + font cmap probing only.
- **Structure overlay is orthogonal to the blitter.** Any rung can have a structure contour layer overlaid where edges are strong; the user keeps both behaviors via `--mode octant --structure-overlay`.

## §Caps — terminal capability detection

New `src/terminal_caps.{hpp,cpp}`:

```cpp
struct TerminalCaps {
  bool truecolor = false;
  int  ansi_colors = 16;            // 16 / 256 / 24bit
  int  unicode_version = 0;         // best estimate: 13 / 15 / 16
  bool kitty_graphics = false;
  bool sixel = false;
  bool iterm_inline = false;
  bool font_has_octants = false;    // cmap probe via FreeType
  bool font_has_sextants = false;
  bool font_has_braille = false;
  std::string term_program;         // for logging
};
```

Signal sources, in order of trust:
1. Environment: `COLORTERM`, `NO_COLOR`, `TERM`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`.
2. Font cmap (Phase I bundled FreeType): test `FT_Get_Char_Index(face, 0x1CD00)`, `0x1FB00`, `0x2800`. If `--font` is set, use that face; otherwise the bundled font.
3. Allowlist by `TERM_PROGRAM`: Kitty / WezTerm / Ghostty / iTerm.app / vscode → assume Unicode 16 + truecolor.
4. Override via `--caps unicode=16,octant,truecolor,no-sixel` for testing.

Never probe with escape sequences that wait for a response.

- **DoD:** capability probe finishes in <5ms on cold start; the resolved `TerminalCaps` is dumped in `--log` and visible via `--caps dump`.

## §Octant — `U+1CD00 + mask` blitter

New `src/octant_renderer.{hpp,cpp}`:

- Resize working frame to `cols*2 × rows*4` so each cell maps to a 2-wide × 4-tall pixel patch.
- Per cell, threshold each sub-pixel by luminance ≥ 0.5 → 8-bit mask using the Unicode 16 octant bit ordering. (Bit order specified in TR; verify against the chart and assert with unit tests on a few patterns.)
- Glyph = `U+1CD00 + mask`; foreground = average color of ink sub-pixels; background = average color of non-ink sub-pixels.
- Unlike braille, sub-pixels are gap-free, so fg/bg are *both* meaningful and produce correct color.

- **DoD:** circle test on a 320×120 cell grid: the rendered circle is visibly rounder and less aliased than halfblock and braille at the same grid; unit tests assert specific bit positions.

## §Sextant — `U+1FB00` block fallback

New `src/sextant_renderer.{hpp,cpp}`:

- 2-wide × 3-tall sub-cell. Same masking idea, different lookup.
- Sextants don't live on a single contiguous block; they are scattered across `U+1FB00..U+1FB3B` with the all-on case at `U+2588` and all-off at space. A 64-entry lookup table maps mask → codepoint.
- Same fg/bg derivation as octant.

- **DoD:** same circle test passes; lookup table covered by exhaustive unit test.

## §AutoMode — ladder resolver

`--mode auto` derives a concrete mode from caps:

```
if caps.kitty_graphics or caps.sixel or caps.iterm_inline and user opt-in:
    pixel
elif caps.font_has_octants and caps.truecolor:
    octant
elif caps.font_has_sextants and caps.truecolor:
    sextant
elif caps.font_has_braille and caps.truecolor:
    braille-color  # see §BrailleColor
elif caps.truecolor:
    halfblock
else:
    structure if user asked for structure-implied features else luminance
```

`--render-mode {text|pixel|hybrid}` (introduced fully in Phase N) gates the `pixel` rung at the top. By default `auto` stays text-only — picking `pixel` requires `--render-mode pixel` or `hybrid`.

- **DoD:** capability matrix table in `docs/blitter-ladder.md` lists, for each `(TERM_PROGRAM, font, --render-mode)` combo, the resolved rung; covered by parameterized tests.

## §BrailleColor — color braille at 2×4

Today's braille is mono. Add color: glyph = U+2800 + mask as before; `fg` = average color of ink dots; `bg` = average color of non-ink. On terminals that render braille glyphs centered with gaps the color blocks look different from octant but still convey image content; document that gap-related artifacts are intrinsic.

- **DoD:** `--mode braille` retains current mono behavior; `--mode braille --color-mode truecolor` enables color braille.

## §StructureOverlay — contour layer on any blitter

The current `renderer.cpp` either runs structure mode *or* halfblock/braille. New: structure mode becomes an optional overlay Pass that runs after any blitter and *replaces* the cell glyph (keeping fg/bg from the blitter) wherever edge magnitude exceeds threshold.

- `--structure-overlay {auto|on|off}`. `auto`: on when `--mode structure` or when the user passes any of `--edge-threshold`/`--dog-sigma`/`--contrast`; otherwise off.
- Implementation: a new `overlay-structure` Pass in the graph; depends on `EdgeField` from the existing sobel/dog Passes and on the blitter's `CellGlyphs`.

- **DoD:** `--mode octant --structure-overlay on` renders octant fills with structure-glyph contour replacements at high-edge cells; the contour glyphs use Phase I's HoG matching.

## §LineLigatures — exploit box-drawing & legacy line glyphs

When the structure overlay fires and adjacent cells have compatible edge orientations, pick connecting glyphs from box-drawing (`─│┌┐└┘├┤┬┴┼`) and legacy line characters instead of `/`,`\`,`|`,`-`. Improves continuity of long contours.

- Implement as a post-pass over `CellGlyphs`: for each strong-edge cell, examine the 4 neighbors and look up a join glyph if a join exists.
- Off by default behind `--line-ligatures`. On terminals with poor box-drawing alignment this can look worse; document it.

- **DoD:** rendering a single rotated rectangle shows continuous box-drawing edges rather than dashed `/`,`\`,`|` segments when `--line-ligatures` is on.

## §Mode — new value `--mode blocks` for §BlockSAD picker

Phase I added a SAD picker for block elements. Wire it as a blitter at the same level as halfblock; usable as a high-fidelity color-block mode for terminals without octant support.

- Sub-cell factor 2×2 (quadrants from `U+2596..U+259F` + halfblocks + full block).
- **DoD:** `--mode blocks` works; SAD picker uses the precomputed bitmap table.

## §Tests
- `terminal_caps_tests.cpp` — env detection, allowlist, override parsing.
- `octant_renderer_tests.cpp` — bit-order, fg/bg sub-pixel averaging.
- `sextant_renderer_tests.cpp` — mask→codepoint lookup table.
- Extended `golden_frame_tests.cpp` for octant / sextant / blocks / color-braille on the existing test images.
- Capability-matrix parameterized test: each `(TERM_PROGRAM, font, --render-mode)` row resolves to a documented mode.

## §Bench
- Add octant / sextant / blocks rows to the BENCHMARKS.md fps table.
- Bytes-per-frame for octant truecolor vs halfblock truecolor at the same cell grid: confirm octant emits ~1× ± ~10% (same per-cell SGR cost, slightly larger glyph byte count).

## §Files
New: `src/terminal_caps.{hpp,cpp}`, `src/octant_renderer.{hpp,cpp}`, `src/sextant_renderer.{hpp,cpp}`, `src/blocks_renderer.{hpp,cpp}`, `src/structure_overlay.{hpp,cpp}`, `src/line_ligatures.{hpp,cpp}`, `docs/blitter-ladder.md`.
Modified: `src/cli.cpp` (new flags + `--mode auto`), `src/renderer.cpp` (graph integration), `src/braille_renderer.cpp` (color extension).

## Pitfalls
- Octant bit ordering: the Unicode chart enumeration is *not* a simple raster scan. Encode the mapping in a table and test it against the published codepoint chart, not from intuition.
- Probing terminal capability with escapes that need a response will hang under `script(1)`/`tmux nested`/serial sessions. Use env + cmap only.
- Sextants have gaps in the Unicode block (`U+1FB3C..U+1FB3F` are not sextants). Lookup table, not arithmetic.
- Color braille on terminals that render braille with extra spacing looks like color stripes; this is a font issue, not your bug — document and offer `--mode halfblock` as the recommended fallback.
- Box-drawing ligature joins assume aligned cell boxes; ITerm and Ghostty mostly comply, terminal.app on macOS does not. Default off.
