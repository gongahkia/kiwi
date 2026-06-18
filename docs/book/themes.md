# Themes

Themes control frame colors and default charset. The CLI accepts:

```bash
kumeyuri render diagram.mmd --theme github
```

SVG output also accepts a dark-mode companion theme:

```bash
kumeyuri render diagram.mmd --format svg --theme github --dark-theme tokyo-night > diagram.svg
```

`--dark-theme` is SVG-only.

## Built-in themes

| Theme | Charset | Background | Foreground | Accent |
| --- | --- | --- | --- | --- |
| `default` | ASCII | `#101418` | `#e6edf3` | `#58a6ff` |
| `mono` | ASCII | `#000000` | `#ffffff` | `#ffffff` |
| `tokyo-night` | Unicode | `#1a1b26` | `#c0caf5` | `#7aa2f7` |
| `github` | Unicode | `#ffffff` | `#24292f` | `#0969da` |
| `dracula` | Unicode | `#282a36` | `#f8f8f2` | `#bd93f9` |
| `print-mono` | ASCII | `#ffffff` | `#000000` | `#000000` |

`print-mono` is intended for print/PDF pipelines that need high-contrast
monochrome output and ASCII glyph fallback.

## Charset override

Use `--charset ascii` for plain text targets with limited glyph support:

```bash
kumeyuri render diagram.mmd --format text --theme tokyo-night --charset ascii
```

Use `--charset unicode` when box-drawing glyphs are acceptable:

```bash
kumeyuri render diagram.mmd --format text --theme github --charset unicode
```

## Renderer options

| Option | Applies to | Purpose |
| --- | --- | --- |
| `--theme` | text, SVG, raster, TUI timeline frames | Base colors and default charset |
| `--dark-theme` | SVG | Adds `prefers-color-scheme: dark` colors |
| `--charset` | text, SVG, raster, TUI timeline frames | Overrides theme charset |
| `--width` | text, SVG, raster, TUI timeline frames | Pads or constrains frame width in cells |
| `--padding` | SVG and raster | Adds pixel padding around rendered frame |
| `--font` | SVG and raster | Sets the rendered font family |
