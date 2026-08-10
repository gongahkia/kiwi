# ADR 0039: macOS native feasibility

## Research result

This assessment ran on Fedora Linux 43 x86_64, not macOS. `xcrun` and
`osxcross` are absent. **No access** was available to a macOS version or
architecture, Xcode toolchain, Cocoa desktop, Metal adapter, Core Text font
database, NSPasteboard, IME, accessibility APIs, or a high-DPI display.

The checked-in wgpu-native v29.0.1.1 dependency has only Linux
`libwgpu_native.so`/`.a`; `script/bootstrap` rejects every non-Linux-x86_64
host and downloads the Linux archive, while `script/build-native` creates a
Linux `.so` with `pkg-config`. The current C bridge selects GLFW Wayland/X11
native handles and Vulkan. It therefore cannot build or run as a macOS target.

The pinned header does declare both `WGPUBackendType_Metal` and
`WGPUSurfaceSourceMetalLayer`, whose layer is a `CAMetalLayer *`. Upstream wgpu
lists Metal as first-class on macOS/iOS and wgpu-native publishes macOS binary
releases. GLFW exposes Cocoa `NSWindow` and `NSView` handles and documents that
macOS framebuffer size can change independently of window size as content scale
changes. Those facts establish possible seams; they are not evidence that the
pinned wgpu binary, Cocoa view/layer lifetime, or Kiwi renderer works on macOS.

`platform.window` already queries GLFW framebuffer size and content scale, but
its callbacks and renderer recreation path have only Linux evidence. The font
resolver directly loads Fontconfig; Core Text offers font descriptors and
cascading, but no Core Text provider is implemented. `process.pty` is POSIX in
shape, yet its LuaJIT FFI depends on Linux `libutil` loading and `execvpe`; its
macOS ABI, child environment, resize, and cleanup behavior remain unknown.

## Minimum implementation backlog

1. Split bootstrap/build selection from the Linux archive and `.so` naming.
   Pin a checksum-verified matching macOS wgpu-native archive for each supported
   architecture, record the macOS/Xcode/GLFW/LuaJIT toolchain, and retain the
   existing Linux route unchanged.
2. Split the native bridge into common WGPU code and a macOS Objective-C bridge.
   The macOS bridge must acquire the GLFW Cocoa view on the GLFW main thread,
   own a `CAMetalLayer` lifetime, create the exact pinned Metal-layer surface,
   request Metal explicitly, and report window/surface failures at the platform
   boundary. It must not expose Cocoa or WGPU handles to terminal state.
3. Put platform font discovery behind the existing path-and-face boundary.
   A macOS provider may resolve a configured file first and use a tested Core
   Text descriptor/cascade path for fallback. Do not substitute Core Text
   shaping for Kiwi's existing FreeType/HarfBuzz ownership without separate
   text-equivalence evidence.
4. Make the POSIX session contract explicit and compile its macOS implementation
   against the target host. Verify spawn, inherited environment, bounded reads,
   `TIOCSWINSZ`, EOF, child reaping, and Ctrl-C behavior before reusing it.
5. Keep GLFW character input, clipboard, focus, and content-scale handling in
   `platform.window`. Test NSPasteboard permissions/failures, committed input
   and IME scope, regular-to-Retina movement, minimize/restore, and the future
   accessibility adapter independently.

## Required macOS validation matrix

| Area | Required native evidence |
| --- | --- |
| target | macOS version/architecture, Xcode version, pinned archive checksum, GLFW and LuaJIT ABI |
| GPU/window | Cocoa view + CAMetalLayer surface, Metal adapter/device/shader/present, resize/minimize/close |
| scale | framebuffer and content-scale transitions between normal and Retina displays, resulting grid/font/renderer recreation |
| PTY | shell output/input, resize, EOF, reaping, and interrupt behavior |
| text | configured primary font, fallback CJK/combining/emoji behavior, provider failure path |
| input/system | committed keys, clipboard read/write failure and success, IME limitation, accessibility adapter smoke |
| regressions | focused macOS tests plus unchanged Linux `make check` |

On a supported macOS host, after the target-specific bootstrap/build support
exists, the interactive smoke command is:

```sh
KIWI_MAX_FRAMES=900 make run ARGS='-- /bin/sh -c "printf kiwi-macos-smoke; sleep 15"'
```

During those 15 seconds, resize, minimize/restore, type a committed character,
paste a short UTF-8 string, and close the window. Record the target/toolchain,
observable result, and failure text. This is a proposed future-host command;
the current bootstrap intentionally rejects macOS, so it has not been run.

## Decision

Defer [issue #143](https://github.com/gongahkia/kiwi/issues/143). macOS support
has a bounded architecture route, but there is no macOS host or target binary
to validate the required native behavior. Do not add guessed Cocoa, Core Text,
or platform FFI branches. `make check` is Linux regression evidence only and
cannot prove a macOS target.

## References

- [wgpu supported platforms](https://github.com/gfx-rs/wgpu)
- [wgpu-native binary releases](https://github.com/gfx-rs/wgpu-native)
- [GLFW native access](https://www.glfw.org/docs/latest/group__native.html)
- [GLFW window and content-scale guide](https://www.glfw.org/docs/latest/window.html)
- [Apple CAMetalLayer documentation](https://developer.apple.com/documentation/quartzcore/cametallayer)
- [Apple Core Text documentation](https://developer.apple.com/documentation/coretext/)
- [Apple NSPasteboard documentation](https://developer.apple.com/documentation/appkit/nspasteboard)
- [ARCHITECTURE.md](../ARCHITECTURE.md)
