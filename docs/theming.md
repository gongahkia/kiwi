# Theme Authoring

This document describes the intended `.kumetheme.toml` shape for custom themes.
Runtime loading and `kumeyuri theme` commands are tracked separately in
`TODO.md`; the current renderer only ships built-in themes.

## Current built-ins

Built-in themes live in `crates/kumeyuri-core/src/theme.rs`:

| Theme | Charset | Use |
| --- | --- | --- |
| `default` | ASCII | Conservative dark output |
| `mono` | ASCII | High-contrast monochrome |
| `tokyo-night` | Unicode | Dark docs/editor output |
| `github` | Unicode | Light README/docs output |
| `dracula` | Unicode | Dark presentation output |
| `print-mono` | ASCII | Print/PDF paths |

## Proposed file shape

```toml
name = "solarized-light"
charset = "unicode"

[colors]
background = "#fdf6e3"
foreground = "#073642"
accent = "#268bd2"
edge = "#586e75"
edge_alt = "#6c71c4"
highlight = "#b58900"
muted = "#657b83"
```

Required fields:

| Field | Values |
| --- | --- |
| `name` | kebab-case theme identifier |
| `charset` | `ascii` or `unicode` |
| `colors.background` | hex RGB |
| `colors.foreground` | hex RGB |
| `colors.accent` | hex RGB |
| `colors.edge` | hex RGB |
| `colors.edge_alt` | hex RGB |
| `colors.highlight` | hex RGB |
| `colors.muted` | hex RGB |

## Role guidance

| Role | Constraint |
| --- | --- |
| `background` | Keep opaque; transparent themes are a separate renderer concern |
| `foreground` | Must meet 4.5:1 contrast against `background` |
| `accent` | Must remain readable for node labels and borders |
| `edge` | Must remain readable for arrows and connector glyphs |
| `edge_alt` | Use only when it still contrasts against `background` |
| `highlight` | Reserve for active animation state |
| `muted` | May be lower emphasis, but still readable |

## Authoring workflow

Until the validator lands, add experimental themes as built-ins:

1. Add the theme to `BuiltInTheme` and `Theme::built_in`.
2. Add a constructor on `Theme`.
3. Add the CLI value in `crates/kumeyuri-cli/src/main.rs`.
4. Update `docs/book/themes.md` and `docs/book/theming.md`.
5. Run theme contrast tests and render a representative SVG/text fixture.

After file loading lands, custom theme review should require:

- TOML parser validation for unknown or missing fields.
- Contrast-ratio check for text-bearing roles.
- Snapshot coverage for text and SVG output.
- A clear fallback when the theme cannot be found.

## Non-goals

- Theme files should not contain executable hooks.
- Theme files should not reference remote URLs.
- Theme files should not override parser or layout behavior.
