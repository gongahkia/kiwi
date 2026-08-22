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
`KIWI_VT_LUAJIT_LIB=/absolute/path/to/libluajit-5.1.2.dylib`.

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
constructs the Cocoa global main menu and dispatches one logical action through
its C-to-Lua callback bridge,
creates two independent Cocoa/Metal surfaces, moves one live PTY
between them, writes and restores a bounded tab/split topology with fresh
shells, resizes the primary drawable after the second window closes, then
stages and launches the project-local `Kiwi-dev.app`.
`make cocoa-menu-smoke` additionally sends the `New Tab` menu action through
that native bridge and verifies the live workspace controller creates a second
tab. It does not qualify interactive menu selection or native product chrome.
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
