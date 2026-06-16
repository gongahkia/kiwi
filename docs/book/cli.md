# CLI reference

## Commands

```text
kumeyuri <COMMAND>
```

| Command | Purpose |
| --- | --- |
| `render` | Render a file to text, SVG, GIF, APNG, WebP, or TUI playback |
| `watch` | Redraw text output when a file changes |
| `play` | Play an animated TUI timeline |

## Render

```text
kumeyuri render [OPTIONS] <FILE>
```

| Option | Values |
| --- | --- |
| `--format` | `text`, `svg`, `gif`, `apng`, `webp`, `tui` |
| `--theme` | `default`, `mono`, `tokyo-night`, `github`, `dracula` |
| `--dark-theme` | `default`, `mono`, `tokyo-night`, `github`, `dracula` |
| `--charset` | `ascii`, `unicode` |
| `--width` | Positive cell count |
| `--padding` | Pixel count |
| `--font` | Font family |

`--format` defaults to `text`.

Examples:

```bash
kumeyuri render diagram.mmd
kumeyuri render diagram.mmd --format svg --theme github --dark-theme tokyo-night > diagram.svg
kumeyuri render diagram.mmd --format webp --padding 12 > diagram.webp
kumeyuri render diagram.mmd --format tui
```

## Watch

```text
kumeyuri watch <FILE>
```

`watch` renders text output, listens for file changes, and redraws in place.

## Play

```text
kumeyuri play [OPTIONS] <FILE>
```

| Option | Purpose |
| --- | --- |
| `--speed <FACTOR>` | Override timeline speed |
| `--loop` | Repeat playback |

Interactive controls:

| Key | Action |
| --- | --- |
| Space | Pause or resume |
| Right arrow | Step forward |
| Left arrow | Step backward |
| `r` | Restart |
| `q` | Quit |
