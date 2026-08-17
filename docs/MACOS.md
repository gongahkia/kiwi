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

`make cocoa-smoke` additionally round-trips a fixed UTF-8 string through a
private AppKit pasteboard, checks the bounded `NSAccessibilityStaticText`
projection, creates two independent Cocoa/Metal surfaces, resizes the primary
drawable after the second window closes, then stages and launches the
project-local `Kiwi-dev.app`.
`make release-check` additionally launches an extracted release `Kiwi.app`
through LaunchServices after checking archive reproducibility. It
does not read or replace the user's general clipboard, so it is not a test of
third-party clipboard-manager behavior or rich clipboard formats.

NSAccessibility receives a bounded active-pane text element and update/focus
notifications. No VoiceOver session has been tested, so this is an adapter
implementation rather than a screen-reader compatibility claim. GLFW supplies
committed Unicode input and clipboard support; IME preedit remains unavailable,
matching Kiwi's existing input scope.

The bootstrap script can select the matching macOS x86_64 wgpu-native archive,
but that path has not been compiled or run on an Intel Mac. The macOS bundle
launcher is ad-hoc signed only so LaunchServices can start it reproducibly; it
has no Developer ID signature or notarization, and distribution readiness is
outside the current support claim.
