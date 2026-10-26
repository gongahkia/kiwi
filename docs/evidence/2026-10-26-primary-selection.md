# X11 primary selection qualification — 2026-10-26

This increment implements pointer-primary publication and asynchronous
middle-button paste on X11. The [ownership contract](../adr/0043-x11-primary-selection.md)
separates it from the ordinary clipboard and existing OSC 52 aliases. The broader
[seven-workstream ledger](../IMPLEMENTATION_TRACKER.md) remains incomplete.

## Changes and reproduction

- `e48fa61`: bounded native direct/INCR reader and isolated transfer tests.
- `c7c13ee`: corrected an existing reversed GLFW error ABI and added a real
  NOT_INITIALIZED regression. The old declaration could overwrite a four-byte
  output allocation with a pointer and interpret an error code as a string.
- `55755b2`: native publication, configuration, pointer routing and model tests;
  corrected GTK middle/right mapping and forwarded native pointer modifiers.
- `8d6a83d`: native controller/raw-PTY fixture.
- `de2b595`, `5cf8f54`: cancelled-transfer draining and bounded latest-click queue.
- `1a55494`, `e4b5fe9`, `28da718`: closing-requester retirement, process-wide cap
  and four host gates. `682e316` adds environment-override equivalence assertions.

```sh
make check test-core test-primary-selection
CFLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer' make test-primary-selection
make primary-selection-smoke
KIWI_HOST=gtk make primary-selection-smoke
KIWI_HOST=gtk KIWI_GTK_PRESENTER=gl make primary-selection-smoke
KIWI_HOST=gtk KIWI_GTK_PRESENTER=gl KIWI_GTK_NATIVE_TABS=1 make primary-selection-smoke
```

The last four commands require Linux, native builds and Xvfb. They create private
X servers; their native clipboard writes cannot overwrite the user's desktop
clipboard. GTK must also be built with `make gtk-host`. The native C test has an
unavailable-platform contract on macOS instead of pretending to exercise X11.

## Results

| Check | Result |
| --- | --- |
| Full Lua suite, macOS Intel and Linux x86_64 | 617 tests / 123 suites passed |
| Core without native loading, both platforms | 386 tests / 65 suites passed |
| `make check`, both platforms | Passed full suite, fuzz, 17 PTY cases, readiness/file watchers, process metrics, POSIX oracle, terminfo, CLI and syntax |
| Native X11 reader, normal and ASan/UBSan | Passed direct/INCR Unicode, Latin-1, malformed/oversized data, stalled owner, clipboard isolation and lifetime cases |
| Native macOS unavailable contract | Passed |
| Linux GLFW/WGPU host fixture | Passed with software Vulkan |
| Linux GTK/WGPU host fixture | Passed with software Vulkan |
| Linux GTK GL host fixture | Passed with software GL |
| Linux GTK GL native-tab host fixture | Passed; one initial native tab plus a temporary requester window |
| GTK renderer/host strict C compilation | Passed |
| GTK input callback fixture | Passed, including middle/right mapping and modifier preservation |

macOS `make check` used `5cf8f54`, followed by a full Lua rerun at `28da718`.
Linux `make check` and final host fixtures used `28da718`, in a source archive
with the full hash saved in `BUILD_REVISION`. The final configuration assertion
at `682e316` also passed in the focused primary-selection suite on both platforms.
These are local executions, not an observed hosted CI result. CI now invokes the
native sanitizer fixture and all four isolated host paths.

## What the fixtures establish

The independent X11 owner fixture tests UTF-8, empty/exact-size data, Latin-1
expansion limits, direct properties larger than one poll slice, 1 MiB INCR data
with 70,000-byte chunks, actual overflow despite a zero advertised INCR size,
invalid types/formats, embedded NUL, a nonresponding owner, no owner and repeated
creation/cancellation. The ordinary CLIPBOARD owner remains unchanged.

The model fixture checks grapheme-safe pointer publication on release, no partial
drag publication, empty/oversized selection preservation, async bracketed paste,
mouse modes/Shift policy, release ownership, invalid UTF-8/NUL, state/screen/mode
cancellation, unsupported hosts and configuration. One hundred repeated clicks
retain one active conversion and one latest queued target.

The host fixture selects `primary 中` through the native pointer callback,
reads it through a separate X connection, and checks that ordinary CLIPBOARD
still contains its independent sentinel. It compares exact raw PTY bytes for
bracketed paste and middle/right SGR mouse events, then checks Shift override,
snapshot replacement and focus cancellation. It closes a requester with a
conversion outstanding while its owner remains alive, and retires 16 concurrent
reads while asserting a seventeenth is rejected. No cancelled read reaches the
PTY. These exercises found and closed an actual GLFW BadWindow failure from
destroying a conversion window before its owner replied.

## Limits and remaining work

- This is Xvfb/Mesa software-rendering evidence. DRI3 warnings are expected;
  physical desktops, Wayland, non-US layouts and real modifier events still need
  independent qualification. The GTK callback test alone cannot establish them.
- Native polling bounds property slices and owner waiting; connection setup and
  Xlib server round trips remain synchronous. Final Lua UTF-8 validation and
  paste assembly are bounded by 1 MiB but are synchronous. No displayed-latency
  or power advantage is established by these transfer/load tests.
- Auto-publication of vi selections, keyboard paste-primary bindings, primary
  history and rich formats are not implemented in this increment.
- Ordinary selection highlighting is independent of native PRIMARY ownership.
  Disabling new primary operations does not revoke a previously-published snapshot.
- Windows, colour emoji/fallback consistency, actual-desktop qualification,
  configuration/performance limits and the other unchecked ledger items remain.
