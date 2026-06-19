# Theming

kumeyuri themes are renderer-level defaults for charset and color roles. The
current implementation ships built-in themes; custom `.kumetheme.toml` loading
is not implemented yet.

## Theme roles

| Role | Used for |
| --- | --- |
| `background` | Frame and SVG background |
| `foreground` | Plain text and fallback content |
| `accent` | Node bodies and emphasized diagram elements |
| `edge` | Primary edges, arrows, and connectors |
| `edge_alt` | Alternate edge states and secondary relationships |
| `highlight` | Active animation state |
| `muted` | Inactive or supporting labels |

Each role maps to an RGB color in `crates/kumeyuri-core/src/theme.rs`.

## Built-in themes

| Name | Default charset | Intended use |
| --- | --- | --- |
| `default` | ASCII | Dark terminal output with conservative glyph support |
| `mono` | ASCII | High-contrast monochrome terminal output |
| `tokyo-night` | Unicode | Dark SVG, raster, and modern terminal output |
| `github` | Unicode | Light README/docs output |
| `dracula` | Unicode | Dark presentation or editor-adjacent output |
| `solarized-light` | Unicode | Light Solarized-inspired docs output |
| `solarized-dark` | Unicode | Dark Solarized-inspired terminal/docs output |
| `nord` | Unicode | Dark arctic palette output |
| `catppuccin-mocha` | Unicode | Dark pastel presentation/editor output |
| `high-contrast` | ASCII | Accessibility-first high-contrast output |
| `print-mono` | ASCII | Print/PDF paths that need monochrome output |

Render with a built-in theme:

```sh
kumeyuri render diagram.mmd --format svg --theme github > diagram.svg
```

## Dark-mode SVGs

SVG output can embed light and dark palettes in one artifact:

```sh
kumeyuri render diagram.mmd \
  --format svg \
  --theme github \
  --dark-theme tokyo-night \
  > diagram.svg
```

`--dark-theme` is rejected for non-SVG formats.

## Charset overrides

Themes choose a default charset, but render commands can override it.

```sh
kumeyuri render diagram.mmd --format text --theme github --charset ascii
kumeyuri render diagram.mmd --format text --theme github --charset unicode
```

Use ASCII for logs, plain terminals, and CI comments. Use Unicode when the
target supports box-drawing glyphs.

## Output-specific options

| Option | Applies to | Notes |
| --- | --- | --- |
| `--theme` | text, SVG, raster, TUI | Selects the base built-in theme |
| `--dark-theme` | SVG | Adds `prefers-color-scheme: dark` styling |
| `--charset` | text, SVG, raster, TUI | Overrides the theme charset |
| `--padding` | SVG, raster | Adds pixel padding outside the rendered frame |
| `--font` | SVG, raster | Sets the emitted font family |

## Adding a built-in theme

Built-in themes are code changes, not runtime files. Add the theme in:

| File | Change |
| --- | --- |
| `crates/kumeyuri-core/src/theme.rs` | Add `BuiltInTheme` variant, name mapping, and `Theme` colors |
| `crates/kumeyuri-cli/src/main.rs` | Add the CLI `RenderTheme` value |
| `docs/book/themes.md` | Add the user-facing table row |
| `TODO.md` / `COVERAGE.md` | Update status only when behavior or coverage changes |

Before marking a built-in theme complete, run render snapshots or targeted
theme tests and verify contrast for text-bearing roles.
