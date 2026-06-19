# CLI reference

## Commands

```text
kumeyuri <COMMAND>
```

| Command | Purpose |
| --- | --- |
| `render` | Render a file to text, SVG, GIF, APNG, WebP, or TUI playback |
| `export` | Export a file to portable `.kumecast` JSON or `.kumecast.gz` gzip |
| `convert` | Convert a `.kumecast`/`.kumecast.gz` file back to SVG, GIF, or text frames |
| `lint` | Print layout warnings as text or JSON |
| `layout` | Load an optional AI layout companion binding |
| `watch` | Redraw text output when a file changes |
| `play` | Play an animated Mermaid or `.kumecast` TUI timeline |
| `compat` | Print Mermaid root support for the tracked docs version |
| `plugin` | Install, list, update, disable, or remove cached plugin packages |

## Global Options

| Option | Values |
| --- | --- |
| `--lang` | Locale override, currently backed by en-US messages |
| `--max-input-bytes` | Positive byte limit for diagram source files; defaults to `1048576` |

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
| `--theme` | `default`, `mono`, `tokyo-night`, `github`, `dracula`, `solarized-light`, `solarized-dark`, `nord`, `catppuccin-mocha`, `high-contrast`, `print-mono` |
| `--dark-theme` | `default`, `mono`, `tokyo-night`, `github`, `dracula`, `solarized-light`, `solarized-dark`, `nord`, `catppuccin-mocha`, `high-contrast`, `print-mono` |
| `--charset` | `ascii`, `unicode` |
| `--width` | Positive cell count |
| `--max-label-width` | Positive cell count for flowchart label wrapping |
| `--padding` | Pixel count |
| `--font` | Font family |
| `--allow-external` | Opt in to plugin network fetches (`net.fetch`) |
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

## Export

```text
kumeyuri export [OPTIONS] <FILE>
```

| Option | Values |
| --- | --- |
| `--format` | `kumecast`, `kumecast-gz` |
| `--theme` | `default`, `mono`, `tokyo-night`, `github`, `dracula`, `solarized-light`, `solarized-dark`, `nord`, `catppuccin-mocha`, `high-contrast`, `print-mono` |
| `--charset` | `ascii`, `unicode` |
| `--width` | Positive cell count |
| `--max-label-width` | Positive cell count for flowchart label wrapping |

`--format` defaults to `kumecast`. `kumecast-gz` writes gzip-compressed JSON to stdout.

Example:

```bash
kumeyuri export diagram.mmd --format kumecast > diagram.kumecast
kumeyuri export diagram.mmd --format kumecast-gz > diagram.kumecast.gz
```

## Convert

```text
kumeyuri convert [OPTIONS] <CAST>
```

| Option | Values |
| --- | --- |
| `--format` | `svg`, `gif`, `text` |

`--format` defaults to `svg`. Input may be `.kumecast` or `.kumecast.gz`. Text
conversion prints every cast frame with a duration header.

Examples:

```bash
kumeyuri convert diagram.kumecast --format svg > diagram.svg
kumeyuri convert diagram.kumecast --format gif > diagram.gif
kumeyuri convert diagram.kumecast --format text
```

## Theme

```text
kumeyuri theme list
kumeyuri theme show <NAME>
kumeyuri theme new <FILE> [--name <NAME>]
kumeyuri theme validate <FILE>
kumeyuri theme publish <FILE> [--index-dir <DIR>] [--base-url <URL>]
```

`theme list` uses the project/XDG/bundled discovery order documented in the
theming chapter. `theme show` prints canonical `.kumetheme.toml` for a bundled
or discovered theme. `theme publish` validates a theme, writes canonical TOML
under `<DIR>/themes/`, and updates a static `index.json` suitable for GitHub
Pages at `themes.kumeyuri.dev`.

## Lint

```text
kumeyuri lint [--json] <FILE>
```

`lint` parses the diagram and reports non-fatal layout warnings without rendering
an artifact. Text output is intended for terminals; `--json` emits a stable
report with `file`, `ok`, and `warnings` fields.

## Layout

```text
kumeyuri layout --ai <FILE>
```

`layout --ai` parses the diagram, then loads the optional `kumeyuri-ai` dynamic
library from `KUMEYURI_AI_DYLIB` and checks its ABI symbol before any rewrite is
applied. The main CLI does not link an AI SDK directly.

## Watch

```text
kumeyuri watch <FILE> [--theme-file <FILE>]
```

`watch` renders text output, listens for diagram and optional theme-file
changes, and redraws in place. `--theme-file` reloads the `.kumetheme.toml`
file on every redraw.

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

`play` accepts Mermaid source files plus `.kumecast` and `.kumecast.gz` files.
Cast files are decoded directly without reparsing Mermaid source.

Interactive controls:

| Key | Action |
| --- | --- |
| Space | Pause or resume |
| Right arrow | Step forward |
| Left arrow | Step backward |
| `r` | Restart |
| `q` | Quit |
