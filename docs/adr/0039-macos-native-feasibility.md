# ADR 0039: macOS native support

## Status

Implemented and verified on one Apple Silicon macOS host on 2026-08-17. This
is source-build evidence, not a general macOS compatibility or distribution
claim.

## Decision

Keep the Linux x86_64 path intact and add a separate macOS boundary rather than
introducing Cocoa/Metal APIs into terminal state.

- `script/bootstrap` selects checksum-pinned wgpu-native archives for Linux
  x86_64, macOS arm64, and macOS x86_64. The macOS arm64 archive was fetched,
  verified, compiled, and run; the x86_64 selection is present but unverified
  on Intel hardware.
- The common native bridge selects Vulkan on Linux and Metal on macOS. The
  Objective-C `native/surface_macos.m` obtains GLFW's Cocoa `NSView` on the
  main thread, installs a `CAMetalLayer`, and creates a WebGPU Metal-layer
  surface. Lua terminal state never receives a Cocoa, Metal, or WGPU handle.
- The macOS PTY route uses the system `forkpty` symbols and a C
  `kiwi_execvpe` helper. It searches the explicit child-only `PATH` then calls
  `execve`; Linux continues to delegate to `execvpe`. This preserves the
  existing environment contract without relying on a Linux-only LuaJIT FFI
  symbol.
- The shared FreeType/HarfBuzz/Fontconfig text path remains in use. A Core Text
  provider is not introduced or claimed.
- `native/accessibility_macos.m` attaches one bounded NSAccessibility static
  text element to the GLFW content view. It reports the active pane title and
  viewport text and posts value/focus notifications; it is not a complete text
  accessibility implementation.
- Release and C-SDK packaging use `.dylib` on macOS, include a convenience
  `Kiwi.app` in macOS release archives, and use portable checksum/archive
  commands. Artifacts are unsigned and unnotarized.

## Verification

On the verified Apple Silicon host:

| Area | Evidence | Result and limit |
| --- | --- | --- |
| Native bridge | `make native` | Passed: compiled the common C bridge plus Cocoa/Metal and NSAccessibility Objective-C sources into `libkiwi_surface.dylib`. |
| Regression suite | `make check` | Passed: 332 deterministic LuaJIT tests, parser fuzz, all 10 PTY integration tests, terminfo build, and Lua syntax checks. This does not run Linux binaries. |
| Live window/GPU | `KIWI_MAX_FRAMES=30 make run ARGS='-- /bin/sh -c "printf kiwi-macos-smoke; sleep 2"'` | Passed: a native GLFW/Cocoa/Metal session initialized and printed the child sentinel. This is not a Retina, minimize/restore, or multi-display usability result. |
| C SDK | `make libkiwi-vt-check` | Passed: reproducible macOS archive plus Lua and C consumer checks. The C consumer used the Homebrew LuaJIT library path supplied by the package launcher. |
| Release artifact | `make release-check` | Passed: two macOS archives were byte-identical; checksum, metadata, terminfo, `Kiwi.app` layout, and release-mode launcher checks passed. |
| App launch scaffold | `KIWI_MAX_FRAMES=20 ./script/build_and_run.sh --verify` | Passed: the project-local app bundle staged, launched, and cleaned its tracked child PID. It does not inspect pixels or accessibility clients. |

## Remaining validation and support boundaries

- The implementation has not been compiled or run on macOS x86_64.
- No specific macOS minimum-version claim is made; only the host above is
  verified. A deployment target must be selected and tested before making one.
- No VoiceOver session has exercised the NSAccessibility adapter. Its spoken
  output, rotor/navigation behavior, focus, and selection semantics are
  unverified.
- IME preedit, high-DPI/display transitions, minimize/restore, clipboard
  behavior, and physical rendering fidelity have not been manually tested on
  macOS.
- macOS release archives are not signed or notarized, so they are not a
  distribution-ready application.
- Linux source was retained but was not built in this macOS verification run.

## References

- [wgpu-native binary releases](https://github.com/gfx-rs/wgpu-native/releases)
- [GLFW native access](https://www.glfw.org/docs/latest/group__native.html)
- [GLFW window and content-scale guide](https://www.glfw.org/docs/latest/window.html)
- [Apple CAMetalLayer documentation](https://developer.apple.com/documentation/quartzcore/cametallayer)
- [macOS support notes](../MACOS.md)
