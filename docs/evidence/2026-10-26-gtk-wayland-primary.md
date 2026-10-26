# GTK Wayland PRIMARY qualification

Implementation: `d0cc1c0` (bounded native transfer and GTK host ABI 5),
`2809741` (Wayland parent commit before WGPU presentation).
Committed fixture/CI source: **ee88a6a**. The final compositor run used that
source revision, the rebuilt GTK bridge, and a private display.

## Environment

Ubuntu 24.04 x86_64 container on the shared Intel Mac host; GTK 4.14.5,
libadwaita 1.5.0, GLib 2.80.0, Sway 1.9, wl-clipboard 2.2.1 and wtype.
Sway uses its headless backend and pixman; GTK's parent uses Cairo. WGPU uses
software Vulkan. The fixture provides an isolated runtime directory, disables
XWayland, establishes keyboard focus with a virtual keyboard, and owns every
clipboard client. It does not touch the user's desktop selections.

## Results

- Independent clients: Kiwi publishes Unicode text read by wl-paste; wl-copy
  supplies Unicode, replacement, exact-limit, excessive, NUL-containing and
  truncated-UTF-8 data. Ordinary clipboard contents remain unchanged.
- All three production paths (GTK WGPU, GTK GL, GTK GL native tabs) pass raw PTY
  assertions for bracketed middle/keyboard paste, mouse capture and Shift
  override, cancellation, vi publication and paste into Find without PTY leakage.
- Repeated compositor runs pass. The final fixture floats its temporary closing
  requester, so a cancellation test does not incidentally tile/resize the main
  window during subsequent vi selection. The fixture clears initial blank
  history before testing publication of the visible first row and waits for a
  new publication rather than reusing an earlier copy's status.
- Native transfer tests pass with AddressSanitizer/UndefinedBehaviorSanitizer:
  1 MiB exact/excess bounds, 8 KiB UTF-8 boundaries, invalid data, sixteen-request
  capacity, cancellation before and after stream acquisition, a stalled provider,
  deadline enforcement after delayed dispatch, and recovery after cancellation.
  LeakSanitizer is disabled for the GTK process; no process-wide leak claim.
- Both macOS and Linux pass `make check`: 659 Lua tests across 130 suites,
  18 PTY integration tests, fuzz/readiness/CLI gates and syntax checks for
  372 Lua files. Linux GTK ABI checks and existing X11 host checks also pass.

The initial complete Wayland application test hung in WGPU presentation. Its
[native stack](2026-10-26-gtk-wayland-present-hang.txt) ends in Vulkan present
waiting on Wayland dispatch. Committing the newly created subsurface relationship
on its parent fixes the reproduced first-frame hang. The main loop now reaches
and completes every PRIMARY test stage on that path.

## Evidence and reproduction

- [Final external-client and three-controller transcript](2026-10-26-gtk-wayland-primary.log)
- [Sanitized native-transfer test transcript](2026-10-26-gtk-primary-sanitized.log)
- [Transfer, callback lifetime and presentation contract](../adr/0048-gtk-wayland-primary-selection.md)

Run `make test-gtk-primary` on Linux with GTK development dependencies and Xvfb.
For sanitizer coverage, prefix it with
`ASAN_OPTIONS=detect_leaks=0 CFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer'`.
Run `make gtk-primary-wayland-smoke` with Sway, wl-clipboard, wtype and the normal
GTK/WGPU dependencies. For software Vulkan, select the installed lavapipe ICD
using `VK_ICD_FILENAMES`. The Linux workflow runs these commands and retains the
Wayland transcript. Hosted CI has not been executed from this session.

## Remaining qualification

GLFW/Wayland PRIMARY is not implemented. Headless Sway does not establish
physical-desktop behavior, other compositors, real IME composition, screen-reader
interoperability, fractional/mixed-monitor behavior, suspend/resume, or latency
and power characteristics on a hardware GPU. Those gates remain open.
