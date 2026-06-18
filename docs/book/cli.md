# CLI reference

## Commands

```text
kumeyuri <COMMAND>
```

| Command | Purpose |
| --- | --- |
| `render` | Render a file to text, SVG, GIF, APNG, WebP, or TUI playback |
| `lint` | Print layout warnings as text or JSON |
| `watch` | Redraw text output when a file changes |
| `play` | Play an animated TUI timeline |
| `compat` | Print Mermaid root support for the tracked docs version |
| `plugin` | Install, list, update, disable, or remove cached plugin packages |

## Compat

```text
kumeyuri compat [--mermaid-version <VERSION>]
```

`compat` prints animated partial roots, static-only partial roots, unsupported
roots, and common caveats. `--mermaid-version` is reported beside the tracked
reference version from the current `COVERAGE.md` matrix. If the requested
version differs, output is labelled as unverified for that requested version.

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
| `--max-label-width` | Positive cell count for flowchart label wrapping |
| `--padding` | Pixel count |
| `--font` | Font family |
| `--plugin-allow` | Comma-separated plugin capabilities: `fs.read`, `fs.write`, `net.fetch`, `env.read`, `cache.read`, `cache.write`, `clock.now`, `random.bytes` |

`--format` defaults to `text`.
`render` prints non-fatal layout warnings, such as orphan flowchart nodes and extreme aspect-ratio direction suggestions, to stderr.

Examples:

```bash
kumeyuri render diagram.mmd
kumeyuri render diagram.mmd --format svg --theme github --dark-theme tokyo-night > diagram.svg
kumeyuri render diagram.mmd --format webp --padding 12 > diagram.webp
kumeyuri render diagram.mmd --format tui
```

## Lint

```text
kumeyuri lint [--json] <FILE>
```

`lint` parses the diagram and reports non-fatal layout warnings without rendering
an artifact. Text output is intended for terminals; `--json` emits a stable
report with `file`, `ok`, and `warnings` fields.

## Watch

```text
kumeyuri watch <FILE>
```

`watch` renders text output, listens for file changes, and redraws in place.

## Plugins

```text
kumeyuri plugin install <NAME>
kumeyuri plugin list
kumeyuri plugin update <NAME>
kumeyuri plugin disable <NAME>
kumeyuri plugin remove <NAME>
```

`plugin install` resolves `<NAME>` from npm first, then crates.io. Packages must
carry the `kumeyuri-plugin` keyword. The resolved archive is cached under
`$XDG_DATA_HOME/kumeyuri/plugins/`, or `$HOME/.local/share/kumeyuri/plugins/`
when `XDG_DATA_HOME` is unset.

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
