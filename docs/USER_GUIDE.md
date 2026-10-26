# Kiwi user guide

Kiwi is an experimental GPU-accelerated terminal application for Linux and
macOS. It runs local shells and programs with tabs, splits, Unicode text,
scrollback, search and shell integration. The [product parity assessment](PRODUCT_PARITY.md)
distinguishes implemented behavior from desktop qualification and remaining work.

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

The macOS build supports Intel and Apple Silicon targets. It shares the terminal
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

The current Intel macOS source build, deterministic checks and bounded native
interactions have [recorded evidence](TESTING.md). See [MACOS.md](MACOS.md) for
the support boundary, runtime dependencies, and unverified areas.

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
path during startup. Use `--config PATH` to select one explicit file; an
explicit missing file is an error. Each file is bounded to 64 KiB and 512
lines, has `key = value` syntax, and rejects unknown keys. Environment
variables remain supported and override file values for compatibility with
existing wrappers.

The native `Settings…` menu item on macOS, `Settings` menu item on GTK, and
`Open Configuration` palette action open the effective configuration as text.
If no default source was loaded, that explicit action creates only the
highest-precedence default path (the macOS Application Support path on macOS;
the XDG path elsewhere), with a comment-only template. It creates missing
parents with user-only permissions and creates the file exclusively with
user-only permissions; it never overwrites an existing file. macOS asks the
system text editor to open the path and GTK delegates to the desktop's default
file handler. This is a text-file configuration workflow, not a graphical
preferences editor. The normal launch path remains non-mutating.

```ini
# ~/.config/kiwi/config; see the named themes below
theme = catppuccin-mocha
font-family = "Noto Sans Mono"
font-size = 18
ligatures = true
contextual-alternates = true
scrollback-limit = 4000
scrollbar = always
ambiguous-width = 1
foreground = #d8dee9
background = #2e3440
palette-1 = #bf616a
selection-color = #5e81ac
search-color = #ebcb8b
hyperlink-color = #88c0d0
command-regions = true
command-region-color = #88c0d0
mouse-shift-capture = false
osc52-read = deny
osc52-write = false
osc9-notifications = off
osc9-progress = off
notify-on-command-finish = never
notify-on-command-finish-after = 5
# keybind = ctrl+alt+t = new-tab
# keybind = ctrl+a > n = new-window
# command-palette-entry = title:"Reload, safely", description:"Reload the trusted \"theme\".", action:reload-config
```

`F6` is the default binding for `reload-config`; it can be remapped or removed.
On the WGPU application path, saving a configuration or referenced theme file
also reloads it after 200 ms without another observed edit. Native kqueue
(macOS) or inotify (Linux) events wake the existing host readiness worker;
there is no periodic configuration-file scan. Atomic editor saves and later
creation of missing files are watched too. `live-config-reload = false`
disables automatic reload; F6 still works and can re-enable it. An invalid
save leaves a bounded error in the window title until a successful reload;
the full diagnostic is also written to stderr. Saving comments alone does not
rebuild resources. The GTK GL prototype retains manual reload only.
Kiwi validates the full replacement, including its action map and theme, before
changing live resources; an invalid file leaves the current configuration
active. Theme, renderer colors, font settings, host-effect policy, local
actions, and the `scrollbar` policy reload in the same session.
On the WGPU application path, Kiwi stages every pane's state, font and renderer
before replacing live resources. Failed font, layout or GPU allocation keeps
the existing session usable; terminal replies and child resize happen only
after activation. Staging temporarily duplicates retained state and GPU
resources, so large histories can increase reload time and peak memory.
`ambiguous-width` and `scrollback-limit`
remain startup-only, because changing either would require semantic grid reflow
or history retention changes; Kiwi reports that limitation instead of partially
applying the file.

`mouse-shift-capture` chooses what a primary-button Shift drag does while an
application has enabled DEC mouse tracking. The default `false` makes Shift a
local-selection override unless the application asks to capture it with
XTSHIFTESCAPE (`CSI > 1 s`). `true` reverses that default, allowing selection
only after the application explicitly permits it (`CSI > s` or `CSI > 0 s`).
`always` forces application capture and `never` forces local selection. Once a
local drag begins, its motion and release stay local. This is a host policy:
Kiwi does not infer whether Shift is meaningful to a particular application,
and non-Shift modifiers do not override mouse reporting. The setting reloads
with the rest of the local input policy. `KIWI_MOUSE_SHIFT_CAPTURE` accepts the
same four values.

`scrollbar = always|never` controls Kiwi's renderer-drawn primary-screen
scrollback overlay; it defaults to `always`. `always` means the overlay is
eligible when the primary screen has retained history, not that an empty
history displays a disabled track. The overlay's track click and thumb drag
move only the local history viewport, including when an application has mouse
tracking enabled; normal pointer events outside it retain the application's
mouse-mode ownership. It is hidden on the alternate screen. This is presently
implemented by the WGPU and experimental `KIWI_GTK_PRESENTER=gl` presenters,
not as a Cocoa/GTK platform scrollbar widget or accessibility range/value
control. `KIWI_SCROLLBAR` accepts the same two values.

At launch, these documented command-line settings use the same validation as
the file and take precedence over file and `KIWI_*` environment values:

```sh
kiwi --theme dracula --appearance dark --font-family "Noto Sans Mono" --font-size 18
kiwi --theme-file /absolute/path/to/colours.conf --scrollback-limit 4000 --scrollbar never --shell-integration none
```

The accepted flags are `--theme`, `--theme-file`, `--appearance`,
`--font-family`, `--font-size`, `--scrollback-limit`, `--scrollbar`, and
`--shell-integration`; each needs one non-empty, NUL-free, control-free value.
Later occurrences win, except that `--theme` and `--theme-file` cannot be
combined. The configuration file and environment are read first, then these
flags are reapplied after every successful reload. `--theme-file` remains an
absolute, colour-only trusted input: it cannot set arbitrary Kiwi options or
execute content.

The default local actions are `Ctrl+Tab` (next tab), `Ctrl+Shift+T` (new tab),
`Ctrl+Shift+N` (new window), `Ctrl+Shift+M` (move the active live session to a
new window), `Ctrl+Shift+Alt+M` (choose an existing window for that live
session), `Ctrl+Shift+D` and `Ctrl+Shift+Alt+D` (fresh-shell counterparts,
with the latter choosing an existing window),
`Ctrl+Shift+W` (close pane), `Ctrl+Shift+Enter` (split right), and
`Ctrl+Shift+J` (split down). `Ctrl+Shift+P` opens the command palette.
On macOS, `Command+Shift+P` also opens it. `Command+1` through `Command+9`
select the corresponding tab in its current visible order, within the current
window group. A missing tab is a no-op; `Command+9` means the ninth tab.
`Command+0` still resets font size. Tabs beyond nine remain accessible through
next/previous-tab shortcuts or the tab bar. The `goto-tab-1` through `goto-tab-9`
actions can also be assigned custom shortcuts or palette entries on any host. Moves
preserve the live PTY, terminal state, and
scrollback; duplicates create a fresh default-shell session. A move or
duplicate to an existing window is rejected when there is no other Kiwi window,
and these operations are unavailable while `--record` is active.
The chooser exposes only the other registered windows in this application (at
most 15), never terminal titles, paths, contents, or remote targets. It
revalidates the selected window and its tab/pane capacity when the choice is
confirmed; a rejected live move restores its source exactly once.

On the primary screen, vertical wheel input moves local scrollback while an
application has not enabled terminal mouse tracking. Touchpad-style fractional
deltas accumulate separately for each terminal session; one host event moves at
most 16 rows. Wheel input over an inactive custom-workspace pane first makes
that pane active. Kiwi does not steal application mouse reports or alternate
screen alternate-scroll input.

On macOS, `Ctrl+Shift+T` / `New Tab` creates a new GLFW/Cocoa controller and
joins it to Kiwi's AppKit tab group; `Ctrl+Tab` selects the next AppKit tab.
`Ctrl+Shift+N` / `New Window`, restored windows, and a session moved to a new
window explicitly stay outside that group. Each native tab has its own WGPU
surface, custom split workspace, and PTY set. Normal macOS tab creation is
therefore host-owned, but Kiwi has not implemented native split content. On
Linux, the default GTK route likewise keeps renderer-workspace tabs; the
separately gated `KIWI_GTK_PRESENTER=gl KIWI_GTK_NATIVE_TABS=1` route has
experimental libadwaita pages with independent VT/PTY sessions. That prototype
supports New Tab, Next Tab, and non-final-page Close Pane: it has no splits,
detach/transfer, persistence, manager `host-tab` lifecycle, or graphical Linux
qualification. Session movement to an already open target and a restored
multi-tab workspace still use the existing custom workspace topology.

Use up to 64 bounded `keybind` directives to replace that map. A directive has
the form `keybind = chord = action`, or a sequence such as
`keybind = ctrl+a > n = new-window`. A sequence has two or three chords;
`ctrl`/`control`, `cmd`/`super`, `shift`, and `alt` are accepted modifiers.
Keys are letters, digits, `F1` through `F12`, or `backspace`, `delete`, `down`,
`end`, `enter`, `escape`, `home`, `insert`, `left`, `page-down`, `page-up`,
`right`, `space`, `tab`, and `up`. The actions are `close-pane`,
`command-palette`, `new-tab`, `new-window`, `next-tab`, `reload-config`,
`open-configuration`,
`move-session-new-window`, `move-session-next-window`,
`move-session-select-window`, `duplicate-session-new-window`,
`duplicate-session-next-window`, `duplicate-session-select-window`,
`split-down`, and `split-right`. The two `*-next-window` actions preserve the
older deterministic target route for an explicitly configured binding; the
default bindings and native menus use `*-select-window`. Set a binding or
sequence to `none` to remove it, or use
`keybind = clear` before later directives to start from an empty local action
map. Kiwi rejects bindings where one sequence is a prefix of another, rather
than delay an action ambiguously. A prefix is consumed locally and must be
completed within one second; an unmatched later chord clears it and can begin a
new configured sequence. Pending input clears on focus loss, a successful
configuration reload, or Kitty keyboard flag 8. Product actions are not consumed while the
terminal has negotiated Kitty keyboard flag 8, so disambiguated application
input retains priority. `make key-sequence-smoke` checks a configured
press/release prefix and completion against the live host tab controller.

On macOS, the default GLFW/Cocoa route exposes these actions through its `File`
and `Window` menus, a unified titlebar toolbar (New Tab, Split Right, Split
Down, Commands, and Settings), and a searchable AppKit palette. On Linux,
`KIWI_HOST=gtk` exposes the same actions through the GTK application menu,
resolving each `win.*` action against the active window, and opens the palette
in a searchable GTK dialog. The palette has 38 default built-in entries,
matches title and description text case-insensitively, and accepts up to 64
total entries after configuration. Add an entry with
`command-palette-entry = title:<title>, action:<action>` and optionally
`description:<description>` in any field order. Commas, quotes, and backslashes
inside a field require a quoted value using `\"` and `\\`; title/description
are bounded NUL-free UTF-8 (128/256 bytes), and a directive is bounded to 512
bytes. Up to 128 directives are retained while the final catalogue is capped at
64 entries. An empty `command-palette-entry =` clears the accumulated default
and custom entries before later entries are applied. An entry may invoke only the
documented workspace actions except `command-palette` itself, so it cannot
recurse, execute a command, send text, or emit terminal control bytes. These
menus deliberately define no keyboard equivalents: the configured key map
remains the only local accelerator policy. Selecting a menu item is an explicit
host command and is therefore available even while Kitty keyboard flag 8
reserves physical keyboard input for the terminal. `make cocoa-palette-smoke`
opens the Cocoa palette and selects `New Tab` through the live host tab
controller;
`make gtk-palette-smoke` is the corresponding graphical-Linux gate, and
`make gtk-session-target-smoke` validates the bounded GTK destination-slot
callback. Neither
proves interactive filtering, keyboard navigation, or general product-chrome
behavior.

The macOS `Kiwi.app` bundle additionally exposes a deliberately small
AppleScript command set: `new terminal window`, `new terminal tab`, `next
terminal tab`, `close terminal pane`, `split terminal right`, `split terminal
down`, `reload Kiwi configuration`, and `open Kiwi configuration`. It routes
each request through the same product-action dispatcher as the menus, palette,
and local key map. Set `macos-applescript = false` to unregister that bridge on
configuration reload; its default is `true`. The feature does not expose
terminal input, arbitrary actions, session inspection, or a general
window/tab/terminal object model. macOS must authorize the external client
that sends an automation request. `make cocoa-automation-smoke` validates the
bundle definition and its bounded in-process dispatch, but does not request or
qualify that permission.

Kiwi attempts to persist bounded window geometry plus tab/split topology and
the active tab/pane on normal live-session changes, reporting an I/O failure to
stderr. Successful updates use a temporary file and same-directory rename. It
restores that topology with one fresh default shell per pane at the next launch;
terminal text, scrollback, running processes, command arguments, clipboard
data, and environment values are never written. The current schema is v2 and
the default path is `~/Library/Application Support/io.github.gongahkia.kiwi/workspace-v2.json`
on macOS and `$XDG_STATE_HOME/kiwi/workspace-v2.json` (or
`~/.local/state/kiwi/workspace-v2.json`) on Linux. On the default path, Kiwi
also reads one valid v1 file, drops its process-local controller IDs, and
atomically writes v2 on the next persistence update. An explicit
`KIWI_LAYOUT_PATH` migrates valid v1 content in place. Set
`KIWI_LAYOUT_PERSISTENCE=0` or
`KIWI_LAYOUT_RESTORE=0` to disable one direction, or pass
`--no-restore-layout` to disable both. Malformed, oversized, and future-schema
files are rejected with a diagnostic and never evaluated as code.

When the active shell has emitted a valid OSC 7 `file:` directory, a fresh tab,
split, duplicate, or window starts there only if the URI authority is empty,
`localhost`, or the current machine name (including its short name). Kiwi
percent-decodes the bounded path and lets the child fall back to the process
launch directory if it cannot enter it. Remote or malformed OSC 7 metadata is
never used as a local working directory.

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

`osc52-read` remains `deny` by default. Setting it to `allow` permits a
terminal to query the ordinary clipboard through one `c`, `p`, or `s` OSC 52
selector; Kiwi reads at most 65,536 valid UTF-8, NUL-free bytes and replies to
the PTY only after that validation. It is a static session-wide permission, not
a prompt or per-program grant. `osc52-write` remains `false` by default;
setting it to `true` permits only validated, bounded OSC 52 clipboard writes.
Neither option permits clears, primary/secondary clipboard access, rich data,
or automatic synchronization. `osc9-notifications` and
`osc9-progress` are also `off` by default. Setting either to `system` allows a
validated typed request to reach a host that implements it. GTK currently
submits notifications through the desktop notification service with a
window-owned identifier; the desktop may decline to show them. GTK progress
uses a non-interactive accessible progress bar above its terminal presentation:
states `0`/`1`/`2`/`3`/`4` mean clear/normal/error/indeterminate/paused. On
macOS, `osc9-progress = system` shows the same state in a per-window native
titlebar indicator. When either notification policy is enabled, macOS asks for
alert permission from that trusted configuration choice, not from a terminal
escape sequence. Once granted, Cocoa sends one replaceable local notification
per window and removes it on teardown; system settings or Focus can still
suppress or delay delivery. Requests arriving before permission resolves, or
after it is denied, are rejected without retaining their terminal body. Kiwi
never logs the terminal-supplied notification text.

`notify-on-command-finish` is separate from OSC 9. It consumes only Kiwi's
observed OSC 133 `C` (command execution) and `D` (completion) lifecycle, never
the command or its output. `never` is the default; `unfocused` submits only
when the completing pane/tab is not focused; `always` also submits while it is
focused. `notify-on-command-finish-after` is an integer threshold from zero to
86,400 seconds and defaults to five. The elapsed time is measured between
host-observed `C` and `D` markers, so it is advisory rather than an audited
process-duration measurement. A qualifying completion submits a fixed local
message (with an optional numeric exit status) to the same host notification
bridge as configured OSC 9 notifications. GTK can submit it to the desktop
notification service; a permitted Cocoa/GLFW host can submit its own local
notification. Desktop policy can still suppress either request, and a Cocoa
permission-pending or denied request reports its bounded rejected result once.
`KIWI_NOTIFY_ON_COMMAND_FINISH` and
`KIWI_NOTIFY_ON_COMMAND_FINISH_AFTER` accept the same values for a single
launch.

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

## Colour emoji and fallback fonts

Kiwi renders bitmap colour emoji on macOS and Linux. It uses Apple Color Emoji
on macOS and the installed Fontconfig emoji family on Linux; install a bitmap
font such as Ubuntu's `fonts-noto-color-emoji` package if no suitable font is
available. Flags, skin tones and joined emoji use the font's shaping support.
Emoji keep their artwork colours and fit within their terminal cells.

Font size changes work with bitmap-only strikes. Bold and italic do not distort
colour artwork. A missing character displays `?` without changing the text you
copy. COLRv1 paint graphs and OpenType SVG fonts are not implemented. Details
and limits are in [TEXT.md](TEXT.md).

## Current limits

Kiwi advertises 256 indexed colours and direct RGB SGR through its
`xterm-kiwi` terminfo entry and `COLORTERM=truecolor`; this is not full xterm
or VT certification. Its supported targets are Linux x86_64 and a verified
macOS arm64 source path. It has a bounded Linux AT-SPI provider and macOS
NSAccessibility element, but no validated end-to-end screen-reader result,
Wayland primary-selection qualification, an OSC 52 prompt policy, full
text indexing, command execution UI, or controlled-remote SSH qualification. The
current, precise limits are maintained in the [conformance matrix](CONFORMANCE.md),
[text contract](TEXT.md), [accessibility contract](ACCESSIBILITY.md), and the
repository [README](../README.md#deliberate-limits).

## Everyday pane and text controls

The standard WGPU application exposes these actions through the command palette,
configuration bindings, and native Edit/View/Window menus. The experimental GTK GL
presenter does not yet implement the full workspace action set.

| Operation | Default shortcut | Config action |
| --- | --- | --- |
| Previous tab | Ctrl+Shift+Tab | `previous-tab` |
| Focus adjacent pane | Ctrl+Alt+Arrow | `focus-pane-left/right/up/down` |
| Move nearest divider by two cells | Ctrl+Alt+Shift+Arrow | `resize-pane-left/right/up/down` |
| Zoom active pane / restore splits | Ctrl+Shift+Z | `toggle-pane-zoom` |
| Equalize all dividers | Command palette | `equalize-splits` |
| Cycle panes | Command palette | `next-pane`, `previous-pane` |
| Increase / decrease / reset font | Ctrl+Plus / Ctrl+Minus / Ctrl+0 | `increase-font-size`, `decrease-font-size`, `reset-font-size` |
| Oldest history / live output | Ctrl+Shift+Home / End | `scroll-to-top`, `scroll-to-bottom` |
| Clear saved history, preserve screen | Ctrl+Shift+K | `clear-scrollback` |
| Select retained text | Ctrl+Shift+A | `select-all` |
| Enter / leave vi navigation | Ctrl+Shift+Space | `toggle-vi-mode` |

On macOS, Command+C/V/A copy, paste, and select all; Command+F starts search;
Command+G and Command+Shift+G navigate results; Command+K clears history;
Command+Plus/Minus/0 controls font size; Command+Comma opens configuration.
Command+T/N/W creates a tab/window or closes the pane, Command+D splits right,
Command+Shift+D splits down, and Command+Shift+Enter toggles pane zoom.
Configuration bindings override these defaults, including `cmd+c=none`.
The `copy`, `paste`, `search`, `search-regex`, `search-next`, and `search-previous` actions can also
be assigned to custom bindings or palette entries.

Find starts with Ctrl+Shift+F (Command+F on macOS). Use the **Find Regular
Expression** palette action, Ctrl+Shift+Alt+F, or Command+Option+F on macOS to
start a regex query. Alt+R toggles literal/regex mode while editing and preserves
the query. Enter searches forward; Shift+Enter searches backward. Escape clears
Find and cancels pending work. Clipboard paste goes into the query while editing.
The title shows the mode, progress, result count, invalid expression, or limit
reached. Output or resizing invalidates results; restart Find to search new text.

Matching is case-sensitive over Unicode scalars, without normalization or case
folding. Soft-wrapped rows form one logical line; hard newlines separate searches.
Results expand to whole grapheme cells. Regex supports `.`, anchors, classes,
groups, alternation, greedy repetition, ASCII `\d`/`\w`/`\s` and word boundaries.
It uses leftmost-longest matching; backreferences, lookaround, lazy quantifiers
and Unicode property escapes are rejected. Literal matches can overlap; regex
matches do not overlap. Erased trailing cells are excluded; printed spaces remain.

Limits are 1,024 query bytes, 512 compiled states, 32 group levels, repetition
counts through 128, 65,536 scalars per logical line, 256 retained matches, and
33,554,432 work units per search. A limit produces an explicit partial-result
status. Work yields between event-loop slices; Escape does not wait for the
whole history. These are bounded scans, without an index or live incremental
updates as new terminal output arrives. See [the search contract](CONFORMANCE.md#scrollback-search).

Vi mode uses a separate, nonblinking cursor over the current screen and retained
history. It never moves the application's cursor. Toggle it with
Ctrl+Shift+Space or **Toggle Vi Mode** in the palette. `i` or Ctrl+C exits and
returns to live output; Escape cancels a motion, selection, or Find query.
Applications requesting all keys through Kitty's keyboard protocol own the
activation shortcut; the palette remains available. Once vi is active, global
product shortcuts remain available and vi owns command text, repeats, releases,
and pointer events. Clipboard paste is disabled unless editing a Find query.

| Vi command | Effect |
| --- | --- |
| `h j k l` / arrows | Move by whole grapheme cells or physical rows |
| `w b e` / `W B E` | Next word, previous word, word end; uppercase uses whitespace-separated words |
| `0 ^ $` / Home / End | Row start, first nonspace cell, last occupied cell |
| `gg G` | Oldest / newest retained row; a numeric prefix chooses a row |
| `H M L`, `zz` | Top / middle / bottom of viewport; center cursor |
| Ctrl+B/F, Page Up/Down; Ctrl+U/D | Page; half page |
| Ctrl+Y/E | Scroll one row |
| `v V`, Ctrl+V, Alt+V | Character, logical-line, rectangular, word selection |
| `y` | Copy selection and clear it after a successful clipboard write |
| `f F t T`, `; ,` | Find a character forward/backward, stop on/before it, repeat/reverse |
| `%` | Find matching bracket, including nested brackets |
| `/ ?`, `n N` | Regex Find forward/backward from the cursor; repeat/reverse result navigation |
| Enter | Open the explicit OSC 8 hyperlink under the vi cursor |

Numeric prefixes are bounded at 9,999. Scanning motions yield after at most
4,096 work units per slice and stop at 8,388,608 total units with a visible limit
status. Line and word selections expand across soft wraps with the same limits;
incomplete selections cannot be copied. Output changes cancel pending scans; history eviction clamps the cursor
and clears selections whose anchor was removed. Resize remaps the cursor and
ordinary selection; rectangular selections clear because their geometry changes.
Rectangular copy includes spaces and separates physical rows with newlines.
Both copying and highlighting expand a cut wide character to its full cell span.
This is terminal navigation, without Vim editing, registers, or macros.
X11 primary selection is described below.

`make vi-smoke` checks live host input against a raw PTY receiver and a private
clipboard bridge. `make selection-smoke` checks rectangular and linear highlight
coverage through native GPU framebuffer readback; both require a graphical session.

**Open URL Hints** in the palette, Ctrl+Shift+U, or Command+Shift+U on macOS labels
links in the current viewport. **Copy URL Hints** uses Ctrl+Shift+Alt+U or
Command+Shift+Option+U. Type a displayed label to preview its destination in the
window title, then press Enter to open or copy it. Tab/Shift+Tab and Up/Down cycle
the remaining labels. Backspace removes a typed letter; Escape or Ctrl+C cancels;
Ctrl+R rescans. Ctrl+Shift+C or Command+C copies the selected destination in either
mode. Typing a label never opens a link by itself. With only one result, Enter
activates it directly. Paste and pointer input are captured while hints are active.

Discovery recognizes ASCII `http://`, `https://`, and `mailto:` text and eligible
OSC 8 links. An OSC 8 link's actual destination takes precedence over displayed
text. URLs can cross soft wraps and viewport edges; only intersecting links get
labels. Trailing sentence punctuation and unmatched closing brackets are trimmed
from plain-text URLs. Unicode URLs, file/custom schemes, configurable hint regexes
and arbitrary hint commands are not supported. Existing Ctrl+Shift+O opens the
explicit link under the application cursor without entering hints mode.

Hints retain at most 256 links with destinations up to 2,048 bytes. Discovery yields
after 4,096 work units and stops at 262,144 units with a visible partial-result
status. Most labels have one or two letters; densely packed one-cell links use
pages of single letters, navigated with Page Up/Down. Output, scrolling, resizing
or changing screens invalidates the targets; Ctrl+R restarts from the new view.
Applications requesting all Kitty keys own the activation shortcut; use the
palette in that case. Once active, hints capture text, repeats and releases before
child protocol encoding and preserve ordinary text selection and vi mode.

`make hints-smoke` checks native host input against a raw PTY receiver with private
opener/clipboard substitutes. `make hints-framebuffer-smoke` verifies badge pixels
even with a saturated glyph cache. `make bench-hints HINT_HISTORY=10000` measures
bounded model work with retained history and dense OSC 8 targets; it does not
measure input-to-display latency.

On Linux **X11**, completing a mouse selection makes a snapshot available for
middle-click paste. This is separate from the ordinary clipboard: Ctrl+Shift+C/V
still use CLIPBOARD. Double/triple-click word/line selections publish on release.
Empty or oversized selections leave the previous primary snapshot intact; merely
clearing the highlight does not erase it. Completed vi selections also publish automatically while their window is focused.
Shift+Insert pastes PRIMARY on Linux; Ctrl+Shift+Insert explicitly copies the
current selection to PRIMARY. The palette exposes **Copy to Primary Selection**
and **Paste Primary Selection**, and both actions accept custom bindings.
Primary paste goes into an active Find query; editing that query while the read
is pending cancels delivery. Vi mode outside Find and URL hints reject paste.

Set `primary-selection = false` (or `KIWI_PRIMARY_SELECTION=false`) to disable new
primary-selection operations. This does not revoke an existing native snapshot.
When a terminal program captures mouse input, middle click belongs to that
program; Shift+middle-click uses the existing `mouse-shift-capture` policy.
Vi/hints/Find input ownership takes precedence. Reads are asynchronous with a
one-second owner-response deadline and a 1 MiB UTF-8 limit. Failed reads send no
partial input; accepted text uses bracketed-paste framing when enabled. Changing
focus, pane or input mode cancels pending delivery. macOS and Wayland do not use
this X11 path. See [the ownership and lifetime contract](adr/0043-x11-primary-selection.md).

`make test-primary-selection` tests native transfers and limits.
`make primary-selection-smoke` checks host input against a raw PTY; it creates a
private Xvfb server so its clipboard writes cannot affect the user's desktop.

Font size changes apply to the current window without editing the configuration.
Reset restores the last successfully loaded configured size. Sizes that cannot fit
all existing panes are rejected. Zoom is temporary and is not saved in the layout;
opening or closing a split restores the split view. Divider ratios and focus are
saved when layout persistence is enabled. Directional focus stops at the edge;
cycling panes wraps within the current tab. Copying omits unused padding at line
ends while preserving printed spaces and Unicode grapheme text.

`make interaction-smoke` exercises live pane creation, focus, resizing, zoom,
font reset, and search through the native action bridge. It requires a graphical
session and always disables layout restore and persistence.

## Explicit launches

`kiwi --working-directory /absolute/path -- command args...` starts that command
in that directory. Arguments after `--` are passed unchanged, including spaces
and empty arguments. A nonexistent directory exits the child with status 126
before executing the command. A relative working directory or empty command
is an argument error. `--help` and `--version` work without opening a window or
loading native graphics libraries.

An explicit command or working directory disables saved-layout restore and
persistence for that launch, so saved shells cannot replace the requested work
and a temporary command cannot overwrite the user's normal workspace topology.
Omit both to retain the normal restore behavior.

## Background transparency

Set `background-opacity = 0.85` in your Kiwi configuration. Values range from
`0` (transparent background) to `1` (the default, opaque). Text, the cursor,
selection overlays and images keep their own opacity. This applies to all cell
backgrounds, including application colours, and to unused space around the grid.
Saving the configuration or invoking Reload Configuration applies it to existing
panes. It does not enable background blur or change window decorations.

The GLFW host requests an alpha-capable framebuffer and selects a supported
surface alpha mode. macOS/Metal is verified locally. Linux/Wayland can use this
path where the compositor and GPU expose alpha; desktop qualification is pending.
GLFW 3.4's X11 Vulkan window path uses the default opaque visual, so background
transparency is currently unavailable there, even with a compositor running.
Transparency requires desktop compositing;
an unsupported surface rejects the configuration instead of silently ignoring it.
The experimental GTK presenters do not currently implement this setting.
Native GPU readback is available with `make appearance-smoke`.
[GLFW 3.4’s X11 window creation](https://github.com/glfw/glfw/blob/3.4/src/x11_window.c#L1809)
shows the opaque default-visual path used with `GLFW_NO_API`.

## Custom shaders

The WGPU renderer supports one custom WGSL postprocessing file per window:

```ini
background-opacity = 0.85
custom-shader = "effects/scanlines.wgsl"
custom-shader-animation = false
```

Relative shader paths resolve against the configuration file containing the
setting. Absolute paths also work; `~` and environment variables are not expanded.
The shader file and configuration are watched when `live-config-reload = true`.
F6 / Reload Configuration also rereads the shader. An invalid or missing shader
during reload preserves the previous effect and the entire live configuration;
the window title reports the error. Invalid startup configuration reports an
error and exits. Remove the setting, or use `custom-shader = ""`, to disable it.

Define this WGSL function (this example leaves the image unchanged):

```wgsl
fn kiwi_effect(color: vec4<f32>, uv: vec2<f32>, time: f32,
               resolution: vec2<f32>) -> vec4<f32> {
  return color;
}
```

`color` is the fully composited terminal pixel, including splits, cursor, images
and overlays. RGB is linear on the preferred sRGB surface, with straight alpha.
`uv` runs from the top-left `(0, 0)` to the bottom-right `(1, 1)`; `resolution`
is the window's physical pixel size. `time` is seconds from the host clock.
`kiwi_sample(uv)` samples another point in the same frame, clamped to its edges.
Return straight RGBA in `[0, 1]`; preserving `color.a` preserves transparency.
Kiwi handles the final surface alpha conversion. Effects do not cover native
window decorations, menus or the command palette.

[Scanlines](../examples/shaders/scanlines.wgsl) and
[grayscale](../examples/shaders/grayscale.wgsl) are working examples. These use
Kiwi's WGSL interface; Ghostty/Shadertoy GLSL files require porting. Shader chains,
previous-frame feedback, external textures and blur behind the window are not
implemented. Files are limited to 64 KiB and are explicitly selected by the user.

Static effects redraw with terminal activity. Set `custom-shader-animation = true`
for time-based effects; this schedules redraws at 30 Hz, pauses presentation when
minimized or synchronized output is active, and backs off on occluded surfaces.
An effect costs one window-sized RGBA texture and one additional GPU pass.
The default opaque configuration without a shader allocates neither.
The experimental GTK GL presenter does not implement custom shaders.

`make shader-smoke` checks effects on opaque surfaces, including X11.
`make appearance-smoke` additionally checks transparency. Both exercise resize
and invalid shader recovery. `make configuration-reload-smoke` checks file watching and transactional
rollback through a live terminal process. The macOS CI workflow runs both types of checks; Linux CI tests opaque shader
output and live reload using Xvfb and software Vulkan.
