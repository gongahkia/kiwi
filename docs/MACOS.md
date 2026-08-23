# macOS support

Kiwi has a verified source-build path on macOS 26.5.2 Apple Silicon. It uses a
GLFW Cocoa window, an Objective-C `CAMetalLayer` bridge, and wgpu-native's
Metal backend; the terminal kernel, HarfBuzz shaping, FreeType rasterization,
and renderer passes are shared with Linux.

## Install and run

```sh
brew install luajit glfw freetype harfbuzz fontconfig giflib libpng pkgconf ncurses
make check
make run
```

`make bootstrap` downloads the pinned `wgpu-macos-aarch64-release.zip`, checks
its SHA-256, and `make native` creates `.build/native/libkiwi_surface.dylib`.
`make release` writes a deterministically ad-hoc-signed, unnotarized local
`kiwi-<version>-macos-arm64.tar.gz`; it contains both `bin/kiwi` and
`Kiwi.app`. Use `./script/build_and_run.sh` for a project-local `.app` launch
path, or the Codex Run action configured in `.codex/environments/`.

The packaged and source launchers require the Homebrew LuaJIT, GLFW, FreeType,
HarfBuzz, Fontconfig, giflib, and libpng runtimes. The C SDK uses
`libkiwi_vt.dylib`; a nonstandard LuaJIT library location can be supplied with
`KIWI_VT_LUAJIT_LIB=/absolute/path/to/libluajit-5.1.2.dylib`. The app bundle's
in-process LuaJIT host also accepts `KIWI_LUAJIT_LIB` (and retains
`KIWI_VT_LUAJIT_LIB` as a compatibility fallback).

## Boundaries and verification

The verified local checks are `make check`, `make libkiwi-vt-check`,
`make release-check`, and a bounded `make run` Metal smoke. They cover the
native build, terminal PTY lifecycle, C SDK, artifact reproducibility, and a
live GLFW/Cocoa/Metal render path.

`make daily-driver-compatibility COMPAT_ARGS='--require-desktop --report artifacts/compatibility.json'`
adds bounded tmux, shell-integration, OSC 8, Neovim, Vim, `top`, private
pasteboard, and optional controlled-SSH evidence. The repository's
`macos-15-intel` CI job is the Intel x86_64 collection path; it verifies the
architecture before running the same suite. It must complete successfully
before Intel macOS can be described as qualified. Current recorded native
macOS evidence remains Apple Silicon.

`make cocoa-smoke` additionally round-trips a fixed UTF-8 string through a
private AppKit pasteboard, checks the bounded `NSAccessibilityTextArea`
projection and `NSTextInputClient` marked/commit/candidate-rectangle lifecycle,
checks that the current Carbon keyboard layout resolves the layout, Shift, and
PC-101 values used for Kitty keyboard flag 4,
constructs the Cocoa global main menu and dispatches one logical action through
its C-to-Lua callback bridge,
installs a unified native titlebar toolbar with New Tab, Split Right, Split
Down, Commands, and Settings actions,
routes active-session OSC 7 metadata to `NSWindow.representedURL` only for an
empty, `localhost`, or current-host authority and clears it for a remote
authority,
groups two independently rendered Cocoa/Metal top-level windows into an AppKit
tab group, moves one live PTY between them, writes and restores a bounded
tab/split topology with fresh shells, resizes the primary drawable after the
second window closes, then stages and launches the project-local `Kiwi-dev.app`.
`make cocoa-menu-smoke` additionally sends the `New Tab` menu action through
that native bridge and verifies the live workspace controller creates a second
tab. `make cocoa-toolbar-smoke` dispatches `New Tab` from the actual AppKit
toolbar item. `make cocoa-palette-smoke` opens the searchable native palette and
programmatically selects `New Tab` through the same controller. Those checks
do not qualify interactive filtering, toolbar/menu selection, keyboard navigation,
tab tearing/off switching, or native in-window workspace chrome.

The OSC 7 bridge does not stat, resolve, or automatically open a path. It is a
titlebar proxy affordance for the active local shell only; remote and absent
metadata clear it rather than presenting a remote path as a Finder URL. The
smokes check local assignment and remote clearing, not interactive Finder
disclosure or a user's actual shell/SSH hostname behavior.

## Bounded AppleScript actions

`Kiwi.app` is a real application process: `native/macos_app_host.c` loads the
LuaJIT application in the executable LaunchServices starts, rather than
forking a second terminal process. The bundle includes `Kiwi.sdef` and
registers raw handlers with `NSAppleEventManager`. This makes a narrow
AppleScript surface usable without exposing terminal contents or a general
control plane.

The commands are `new terminal window`, `new terminal tab`, `next terminal
tab`, `close terminal pane`, `split terminal right`, `split terminal down`,
`reload Kiwi configuration`, and `open Kiwi configuration`. Each is an
accepted/rejected request to the existing product-action dispatcher; it is not
a promise that a later asynchronous configuration reload will succeed. No
command can inject text, execute a shell command, name an arbitrary action, or
inspect a terminal/session object. Kiwi therefore does not yet claim Ghostty's
hierarchical scripting model.

`macos-applescript = true` is the default configuration. Set it to `false` and
reload configuration to remove the bridge from the live app. External clients
must still be allowed to automate Kiwi by macOS; `make cocoa-automation-smoke`
does not initiate that user-consent flow. It validates the staged bundle's
scripting definition and invokes a bounded `New Tab` event in the live bundle
process.
`make release-check` additionally launches an extracted release `Kiwi.app`
through LaunchServices after checking archive reproducibility. It
does not read or replace the user's general clipboard, so it is not a test of
third-party clipboard-manager behavior or rich clipboard formats.

NSAccessibility receives a bounded active-pane read-only text area with value,
visible range, caret/selection range, and update/focus notifications.
`make voiceover-validation` checks that adapter contract on a real Cocoa view,
but cannot enable or assess spoken VoiceOver output; manual VoiceOver
navigation remains required. On macOS, a small `NSTextInputClient` overlay
keeps AppKit marked text, commit delivery, and the candidate rectangle at the
active pane cursor while transiently rendering preedit without mutating the
terminal grid or PTY. Real input-source qualification remains manual.

The bootstrap script can select the matching macOS x86_64 wgpu-native archive,
but that path has not been compiled or run on an Intel Mac. The macOS bundle
launcher is ad-hoc signed only so LaunchServices can start it reproducibly; it
has no Developer ID signature or notarization, and distribution readiness is
outside the current support claim.
