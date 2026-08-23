# Kiwi user guide

Kiwi is a rendering-first terminal research platform for Linux x86_64 and a
verified macOS arm64 source path. It is useful for evaluating the implemented
terminal and renderer contracts, but it is not presented as a daily-driver
terminal emulator or a complete VT/xterm-compatible terminal. Read the
[conformance matrix](CONFORMANCE.md) before depending on a protocol feature.

## Install and start

### Linux source checkout

The Fedora 43 path is the maintained development workflow. From a clean
checkout, install the native prerequisites, bootstrap the pinned native
dependency, run the deterministic checks, and start Kiwi:

```sh
git clone https://github.com/gongahkia/kiwi.git
cd kiwi
sudo dnf install luajit gcc make curl unzip pkgconf-pkg-config ncurses \
  glib2-devel glfw-devel freetype-devel harfbuzz-devel giflib libpng-devel mesa-vulkan-drivers vulkan-loader-devel \
  vulkan-tools fontconfig google-noto-sans-mono-fonts
make bootstrap
make check
make run
```

`make run` builds the native bridge and the `kiwi` terminfo entry, then starts
an absolute `$SHELL`, or `/bin/sh` when `$SHELL` is not absolute. To start a
specific child, put it after `--`:

```sh
make run ARGS='-- /usr/bin/printf "Kiwi\n"'
```

The source workflow is not a system installation: the checkout is the launch
location and `make run` sets the project-local terminfo path for its child.

### macOS source checkout

The verified macOS path is macOS 26.5.2 on Apple Silicon. It shares the terminal
kernel and text stack with Linux, but presents through GLFW Cocoa,
`CAMetalLayer`, and Metal:

```sh
git clone https://github.com/gongahkia/kiwi.git
cd kiwi
brew install luajit glfw freetype harfbuzz fontconfig giflib libpng pkgconf ncurses
make bootstrap
make check
make run
```

The macOS x86_64 bootstrap selection exists but has not been compiled or run on
an Intel Mac. See [MACOS.md](MACOS.md) for the support boundary, runtime
dependencies, and unverified areas.

To display a remote PNG, APNG, or GIF, run the explicit URL helper from inside
that Kiwi shell. It fetches only a user-supplied HTTPS URL and then sends
Kiwi's bounded direct-image graphics stream; it does not make automatic network
requests and does not support video:

```sh
./script/kiwi-image https://images.example/kiwi.png
```

The helper waits for the placement acknowledgement and moves the cursor below
the selected image rectangle before returning, so the next prompt does not
overlap it. `--no-cursor-advance` is available for deliberate layered fixtures.

### Local release artifact

For a relocatable, release-mode artifact for the current supported target, use
a clean checkout:

```sh
make release
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) target=linux-x86_64 ;;
  Darwin-arm64) target=macos-arm64 ;;
  Darwin-x86_64) target=macos-x86_64 ;;
  *) print -u2 "unsupported Kiwi release target"; exit 1 ;;
esac
release="kiwi-$(< VERSION)-$target"
(cd dist && { command -v sha256sum >/dev/null && sha256sum --check "$release.tar.gz.sha256" || shasum -a 256 -c "$release.tar.gz.sha256"; })
tar -xzf "dist/$release.tar.gz"
./"$release"/bin/kiwi --version
./"$release"/bin/kiwi -- /bin/sh
```

Inside the release terminal, use the installed helper for the same explicit
HTTPS PNG, APNG, or GIF path:

```sh
kiwi-image https://images.example/kiwi.png
```

Keep the extracted directory intact. Its launcher finds its own Lua source,
terminfo, WGPU library, and native surface bridge relative to `bin/kiwi`; it
does not install files into `/usr` or modify shell configuration. It still
requires the target's native runtime dependencies. On Linux those are LuaJIT,
GLib/GIO, GLFW, FreeType, HarfBuzz, Fontconfig, giflib, libpng, a Vulkan loader
and driver, and Wayland or X11. On macOS they are the corresponding Homebrew
LuaJIT, GLFW, FreeType, HarfBuzz, Fontconfig, giflib, and libpng libraries; the
archive also contains a deterministically ad-hoc-signed, unnotarized
`Kiwi.app` launcher. It has no Developer ID signature. The
adjacent checksum and `metadata.json` describe the artifact that was built.
The optional `kiwi-image` helper also requires `curl`, `zsh`, and standard GNU
core utilities from the host.

For a pinned Nix package or development shell, use [NIX.md](NIX.md). It has
the same Linux display/driver constraint and does not add a binary cache or
cross-platform support.

Arch/AUR publication is currently deferred; it is not an installation path.
See [AUR.md](AUR.md) for the evidence and the source, license, ownership, and
reproducible-build gates for reconsidering it.

## Configuration

Kiwi reads `$XDG_CONFIG_HOME/kiwi/config`, or
`$HOME/.config/kiwi/config` when XDG is unset. On macOS it then reads
`$HOME/Library/Application Support/io.github.gongahkia.kiwi/config`; values in
that platform-specific file override XDG values. Kiwi never creates either
path. Use `--config PATH` to select one explicit file; an explicit missing file
is an error. Each file is bounded to 64 KiB and 512 lines, has `key = value`
syntax, and rejects unknown keys. Environment variables remain supported and
override file values for compatibility with existing wrappers.

```ini
# ~/.config/kiwi/config; see the named themes below
theme = catppuccin-mocha
font-family = "Noto Sans Mono"
font-size = 18
ligatures = true
contextual-alternates = true
scrollback-limit = 4000
ambiguous-width = 1
foreground = #d8dee9
background = #2e3440
palette-1 = #bf616a
selection-color = #5e81ac
search-color = #ebcb8b
hyperlink-color = #88c0d0
command-regions = true
command-region-color = #88c0d0
osc52-write = false
osc9-notifications = off
osc9-progress = off
# keybind = ctrl+alt+t = new-tab
# command-palette-entry = title:"Reload, safely", description:"Reload the trusted \"theme\".", action:reload-config
```

`F6` is the default binding for `reload-config`; it can be remapped or removed.
Kiwi validates the full replacement, including its action map and theme, before
changing live resources; an invalid file leaves the current configuration
active. Theme, renderer colors, font settings, host-effect policy, and local
actions reload in the same session. `ambiguous-width` and `scrollback-limit`
remain startup-only, because changing either would require semantic grid reflow
or history retention changes; Kiwi reports that limitation instead of partially
applying the file.

The default local actions are `Ctrl+Tab` (next tab), `Ctrl+Shift+T` (new tab),
`Ctrl+Shift+N` (new window), `Ctrl+Shift+M` (move the active live session to a
new window), `Ctrl+Shift+Alt+M` (move it to the next window as a tab),
`Ctrl+Shift+D` and `Ctrl+Shift+Alt+D` (fresh-shell counterparts),
`Ctrl+Shift+W` (close pane), `Ctrl+Shift+Enter` (split right), and
`Ctrl+Shift+J` (split down). `Ctrl+Shift+P` opens the command palette. Moves
preserve the live PTY, terminal state, and
scrollback; duplicates create a fresh default-shell session. A move or
duplicate to an existing window is rejected when there is no other Kiwi window,
and these operations are unavailable while `--record` is active.

Use up to 64 bounded `keybind` directives to replace that map. A directive has
the form `keybind = chord = action`; `ctrl`/`control`, `cmd`/`super`, `shift`,
and `alt` are accepted modifiers. Keys are letters, digits, `F1` through
`F12`, or `backspace`, `delete`, `down`, `end`, `enter`, `escape`, `home`,
`insert`, `left`, `page-down`, `page-up`, `right`, `space`, `tab`, and `up`.
The actions are `close-pane`, `command-palette`, `new-tab`, `new-window`, `next-tab`,
`reload-config`, `move-session-new-window`, `move-session-next-window`,
`duplicate-session-new-window`, `duplicate-session-next-window`, `split-down`,
and `split-right`. Set a chord to `none` to remove its default binding, or use
`keybind = clear` before later directives to start from an empty local action
map. Product actions are not consumed while the terminal has negotiated Kitty
keyboard flag 8, so disambiguated application input retains priority.

On macOS, the default GLFW/Cocoa route exposes these actions through its `File`
and `Window` menus and opens the palette in a searchable AppKit panel. On Linux,
`KIWI_HOST=gtk` exposes the same actions through the GTK application menu,
resolving each `win.*` action against the active window, and opens the palette
in a searchable GTK dialog. The palette has eleven default built-in entries,
matches title and description text case-insensitively, and accepts up to 32
total entries after configuration. Add an entry with
`command-palette-entry = title:<title>, action:<action>` and optionally
`description:<description>` in any field order. Commas, quotes, and backslashes
inside a field require a quoted value using `\"` and `\\`; title/description
are bounded NUL-free UTF-8 (128/256 bytes), and a directive is bounded to 512
bytes. Up to 64 directives are retained while the final catalogue is capped at
32 entries. An empty `command-palette-entry =` clears the accumulated default
and custom entries before later entries are applied. An entry may invoke only the
documented workspace actions except `command-palette` itself, so it cannot
recurse, execute a command, send text, or emit terminal control bytes. These
menus deliberately define no keyboard equivalents: the configured key map
remains the only local accelerator policy. Selecting a menu item is an explicit
host command and is therefore available even while Kitty keyboard flag 8
reserves physical keyboard input for the terminal. `make cocoa-palette-smoke`
opens the Cocoa palette and selects `New Tab` through the live controller;
`make gtk-palette-smoke` is the corresponding graphical-Linux gate. Neither
proves interactive filtering, keyboard navigation, or general product-chrome
behavior.

Kiwi attempts to persist bounded window geometry plus tab/split topology and
the active tab/pane on normal live-session changes, reporting an I/O failure to
stderr. Successful updates use a temporary file and same-directory rename. It
restores that topology with one fresh default shell per pane at the next launch;
terminal text, scrollback, running processes, command arguments, clipboard
data, and environment values are never written. The default path is
`~/Library/Application Support/io.github.gongahkia.kiwi/workspace-v1.json` on
macOS and `$XDG_STATE_HOME/kiwi/workspace-v1.json` (or
`~/.local/state/kiwi/workspace-v1.json`) on Linux. Set `KIWI_LAYOUT_PATH` to
use a different file, `KIWI_LAYOUT_PERSISTENCE=0` or
`KIWI_LAYOUT_RESTORE=0` to disable one direction, or pass
`--no-restore-layout` to disable both. Malformed, oversized, or unknown-schema
files are rejected with a diagnostic and never evaluated as code.

The built-in themes are `kiwi`, `nord`, `light`, `dracula`, `gruvbox-dark`,
`solarized-dark`, `solarized-light`, `tokyo-night`, and `catppuccin-mocha`.
Set `theme = system` to select `theme-dark` (default `kiwi`) or `theme-light`
(default `light`) from the host appearance. `appearance = dark` or `light`
forces that selection; `appearance = system` follows the GLFW Cocoa or GTK
adapter when it reports a change. Explicit `foreground`, `background`, and
`palette-N` values remain in effect across a system-appearance change.

`theme-file = /absolute/path/to/theme.conf` is an alternative to `theme` in
the same configuration layer. It loads only local, absolute, NUL-free files of
at most 32 KiB and 256 lines.
The file may contain `foreground`, `background`, `selection-color`,
`search-color`, `hyperlink-color`, `command-region-color`, and `palette-0`
through `palette-255`, all as colours; it cannot include another file, execute
code, or set general configuration. It must provide foreground and background.
An external theme replaces inherited colour overrides; values written after it
in the same configuration layer are explicit overrides.

`osc52-write` remains `false` by default. Setting it to `true` permits only
validated, bounded OSC 52 clipboard writes; it does not permit reads, queries,
clears, or automatic synchronization. `osc9-notifications` and
`osc9-progress` are also `off` by default. Setting either to `system` allows a
validated typed request to reach a host that implements it. GTK currently
submits notifications through the desktop notification service; the desktop may
decline to show them. On macOS, `osc9-progress = system` shows a per-window
native titlebar progress indicator: states `0`/`1`/`2`/`3`/`4` mean
clear/normal/error/indeterminate/paused. Cocoa notification delivery and GTK progress are unavailable,
so those requests report unavailable rather than succeeding silently. Kiwi
never logs the terminal-supplied notification text.

For example, a source checkout can still use environment-only configuration:

```sh
KIWI_FONT_FAMILY='Noto Sans Mono' \
KIWI_FONT_PX=18 \
KIWI_SCROLLBACK=4000 \
KIWI_AMBIGUOUS_WIDTH=2 \
make run
```

An extracted artifact accepts the same variables before its launcher:

```sh
KIWI_FONT_PX=18 ./kiwi-<version>-<target>/bin/kiwi -- /bin/sh
```

The documented settings are intentionally small:

| Variable | Default | Effect |
| --- | --- | --- |
| `KIWI_FONT` | unset | Readable `.ttf` font path, instead of Fontconfig family selection. |
| `KIWI_FONT_FAMILY` | `monospace` | Fontconfig primary family. |
| `KIWI_FONT_PX` | `20` | Base font pixel size before GLFW content-scale adjustment. |
| `KIWI_LIGATURES`, `KIWI_CALT` | disabled | Set either to `1` to request standard ligatures or contextual alternates. |
| `KIWI_AMBIGUOUS_WIDTH` | `1` | Ambiguous-width policy: use the documented `1` or `2` setting. |
| `KIWI_SCROLLBACK` | `2000` | Primary-screen retained line limit. |
| `KIWI_SELECTION_COLOR` | `#5E81AC70` | Selection highlight, `#RRGGBB` or `#RRGGBBAA`. |
| `KIWI_SEARCH_COLOR` | `#EBCB8B70` | Current scrollback-search highlight, in the same format. |
| `KIWI_HYPERLINK_COLOR` | `#88C0D0FF` | OSC 8 hyperlink underline, in the same format. |
| `KIWI_COMMAND_REGIONS` | disabled | Set to `1` for the built-in visible command/output separator pass. |
| `KIWI_COMMAND_REGION_COLOR` | `#88C0D055` | Command-region separator color, in the same format. |
| `KIWI_SHELL_INJECTION` | `auto` | Set to `none` to disable automatic initial Bash/Zsh/fish/Nushell integration. |

Kiwi injects the versioned Bash, Zsh, fish, and Nushell snippets into its initial
default shell by default, without editing a dotfile. Set
`shell-integration = none` or `KIWI_SHELL_INJECTION=none` to disable it.
Switched shells and explicit commands remain manual; follow
[SHELL_INTEGRATION.md](SHELL_INTEGRATION.md) for source blocks, removal, and
the explicit `kiwi-ssh` remote-terminfo workflow.
The source checkout keeps those snippets in `integrations/v1/`; an extracted
artifact keeps the same versioned directory at `share/kiwi/integrations/v1/`.

### Release-mode defaults

The packaged launcher forces release mode. It ignores development shader reload
and keeps pass metrics/budgets, GPU timestamp instrumentation, renderer
inspector settings, and F2--F5 debug shortcuts off even if their corresponding
environment variables are inherited. `KIWI_DEVELOPMENT=1` is only a source
development route and requires an explicit `KIWI_DEV_SHADER_PATH`; it is not a
release customization mechanism. Trusted local render extensions remain an
explicit opt-in in either mode.

## Safe mode and support

To rule out every configured render extension, start with `--no-extensions`:

```sh
KIWI_RENDER_EXTENSIONS=local.example \
  make run ARGS='--no-extensions -- /bin/sh'
./kiwi-<version>-<target>/bin/kiwi --no-extensions -- /bin/sh
```

Safe mode bypasses the module list before any extension is loaded and also
bypasses extension-cap environment parsing. It does not disable built-in
terminal behavior, change the child command, or provide a sandbox for code
outside Kiwi. If the problem persists in safe mode, capture the smallest child
command that reproduces it.

`kiwi doctor` is the first support command. It is local and offline; its JSON
bundle is capped at 64 KiB and excludes terminal, clipboard, shell, and
arbitrary environment content. Review a bundle before sharing it:

```sh
make doctor ARGS='--json --bundle kiwi-support.json'
./kiwi-<version>-<target>/bin/kiwi doctor --json --bundle kiwi-support.json
```

The report is a fresh environment probe, not an attachment to a running
terminal session. It cannot recover terminal content or prior diagnostics.
[SUPPORT.md](SUPPORT.md) lists the report fields and the minimum useful issue
context.

## Maintained render-extension examples

Kiwi discovers no extension by default, has no marketplace, and makes no
network request to install one. The maintained API v1 examples are limited to
the two modules below. They are trusted local Lua code, not a security sandbox,
and neither can draw or allocate GPU resources under API v1.

| Module | API | Reads | What it demonstrates | Constraints |
| --- | --- | --- | --- | --- |
| `kiwi.renderer.samples.damage_observer` | v1 | `terminal.damage`, `frame.timing` | A semantic observer that requests one 250 ms redraw only after terminal damage. | It owns no GPU state or overlay and must not schedule another idle redraw. |
| `kiwi.renderer.samples.command_region_observer` | v1 | `terminal.command_regions`, `frame.timing` | A semantic observer that retains the current visible boundary count. | It owns no GPU state or drawing capability; useful boundaries require terminal OSC 133 data, such as Kiwi's automatic initial-shell integration or a manual switched-shell setup. |

Enable exactly one sample from a source checkout with `KIWI_RENDER_EXTENSIONS`:

```sh
KIWI_RENDER_EXTENSIONS=kiwi.renderer.samples.damage_observer \
  make run ARGS='-- /usr/bin/printf "sample extension\n"'

KIWI_COMMAND_REGIONS=1 \
KIWI_RENDER_EXTENSIONS=kiwi.renderer.samples.command_region_observer \
  make run
```

Set `KIWI_RENDER_EXTENSIONS` to a comma-separated list to opt into multiple
trusted modules. Disable all of them with `--no-extensions` as shown above, or
remove a module from that variable before restarting. API v1 requires every
declaration to use `api_version = 1`; a new API version needs an explicit
compatibility review rather than an assumed fallback.

`KIWI_EXTENSION_MAX_PASSES` limits optional passes (default `32`) and
`KIWI_EXTENSION_MAX_ANIMATION_HZ` limits optional redraw cadence (default
`60`, valid from `1/60` through `60`). A failing optional callback is disabled
for the current renderer lifetime; built-in passes remain separate. See
[RENDERER_API.md](RENDERER_API.md) for validation, lifecycle, diagnostics, and
the complete API v1 capability boundary.

## Current limits

Kiwi advertises 256 indexed colours and direct RGB SGR through its
`xterm-kiwi` terminfo entry and `COLORTERM=truecolor`; this is not full xterm
or VT certification. Its supported targets are Linux x86_64 and a verified
macOS arm64 source path. It has a bounded Linux AT-SPI provider and macOS
NSAccessibility element, but no validated end-to-end screen-reader result,
primary selection, OSC 52 reads/queries, regular-expression search, full text
indexing, command execution UI, or controlled-remote SSH qualification. The
current, precise limits are maintained in the [conformance matrix](CONFORMANCE.md),
[text contract](TEXT.md), [accessibility contract](ACCESSIBILITY.md), and the
repository [README](../README.md#deliberate-limits).
