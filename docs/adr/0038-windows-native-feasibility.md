# ADR 0038: Windows native feasibility

## Research result

The current Fedora host has `x86_64-w64-mingw32-gcc` 15.2.1, but no Wine/Wine64
runtime and no MinGW GLFW development package. A Windows syntax probe of
`native/surface.c` therefore stopped at the missing target `GLFW/glfw3.h`.
The checked-in wgpu dependency is a Linux x86_64 archive containing only
`libwgpu_native.so`/`.a`; it cannot link a Windows executable. This is build
evidence only. **No access** to a Windows desktop, DX12 adapter, ConPTY host,
Windows font stack, clipboard, IME, or accessibility tooling was available.

The existing bridge is intentionally incompatible with a direct Windows build:
it includes POSIX process/TTY headers, uses `forkpty`, `execvpe`, `waitpid`,
signals, `fcntl`, `TIOCSWINSZ`, `nanosleep`, GLFW Wayland/X11 native handles,
and forces `WGPUBackendType_Vulkan`. `src/kiwi/process/pty.lua` exposes those
POSIX C entry points through LuaJIT FFI. `FontSystem` relies on Fontconfig; the
Linux bootstrap and build scripts pin/download only Linux artifacts.

Upstream wgpu lists Windows DX12 as first-class support and publishes Windows
native binaries, including an x64 GNU build. That establishes a plausible
dependency route, not compatibility with Kiwi's pinned release or a working
surface. Microsoft documents ConPTY as `CreatePseudoConsole` plus synchronous
input/output pipe handles, with `ResizePseudoConsole` for character-grid
resizes. Those I/O/lifecycle requirements are separate from wgpu/window work.

## Scoped implementation plan

1. Split the native bridge into common WGPU request/error/timestamp code and
   platform implementations. The Windows surface must use the exact pinned
   WGPU Windows header/library ABI, an HWND surface descriptor, and an explicit
   DX12 request path; Linux must retain its existing Vulkan/Wayland/X11 path.
2. Replace `process.pty`'s direct POSIX FFI with a small process-session
   interface. A Windows implementation owns inheritable pipes, `HPCON`, child
   process/job lifetime, asynchronous or worker-thread-safe pipe servicing,
   `ResizePseudoConsole`, and explicit close ordering. It must preserve Kiwi's
   bounded input/output queues without pretending process groups or POSIX
   signals exist.
3. Make platform font discovery a narrow provider below existing FreeType and
   HarfBuzz ownership. Fontconfig stays Linux-specific; a Windows provider
   needs an evidence-backed DirectWrite or configured-file resolution path.
4. Keep GLFW committed character input, content scale, clipboard, and focus
   behind `platform.window`; validate Windows keyboard, clipboard, IME/preedit,
   high-DPI, and accessibility behavior separately rather than inferring them
   from Linux callbacks.

## Required Windows validation matrix

| Area | Required native evidence |
| --- | --- |
| build | pinned Windows WGPU archive/checksum, LuaJIT and GLFW target ABI, clean rebuild |
| GPU/window | HWND surface, DX12 adapter/device/shader/present, resize/minimize/close smoke |
| ConPTY | UTF-8 child output/input, resize, EOF, child/job shutdown, Ctrl-C semantics |
| text | primary/fallback CJK/combining/emoji behavior, content-scale transition, font-provider failure |
| input/system | committed keys, clipboard failure/success, IME scope, high-DPI, accessibility adapter smoke |
| regressions | Windows-focused tests plus unchanged Linux `make check` |

## Decision

The recommendation is **defer** [issue #145](https://github.com/gongahkia/kiwi/issues/145).
The refactor is feasible in bounded seams, but a cross compiler without the
target dependencies or a Windows runtime cannot validate the hard requirements.
Do not introduce a guessed ConPTY FFI, Windows package, or DX12 surface before
the matrix has a real Windows host. `make check` remains the Linux regression
gate only; it cannot prove Windows support.

## References

- [wgpu supported platforms](https://github.com/gfx-rs/wgpu)
- [wgpu-native binary releases](https://github.com/gfx-rs/wgpu-native)
- [Microsoft CreatePseudoConsole reference](https://learn.microsoft.com/en-us/windows/console/createpseudoconsole)
- [Microsoft ConPTY session sample](https://learn.microsoft.com/en-us/windows/terminal/samples)
- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [ACCESSIBILITY.md](../ACCESSIBILITY.md)
