# ADR 0025: Wayland IME and window-stack boundary

## Context

Kiwi uses GLFW 3.4 as its Linux window and input owner. The current platform
window installs physical-key and Unicode character callbacks only; its FFI
declarations expose no preedit, composition, text-input focus, cursor-rectangle,
or IME callback. GLFW's character stream is appropriate for committed text and
dead keys, but it cannot represent an in-progress composition.

The researched Fedora 43 session was `XDG_SESSION_TYPE=wayland` with
`WAYLAND_DISPLAY=wayland-0` and `DISPLAY=:0`. `glfwGetPlatform()` returned
`0x00060003` (`GLFW_PLATFORM_WAYLAND`), not its XWayland fallback. Installed
dependencies were `glfw-devel-3.4-5.fc43`, `wayland-devel-1.25.0`, and
`libxkbcommon-devel-1.11.0`. `wayland-info` advertised
`zwp_text_input_manager_v2` version 1 and `zwp_text_input_manager_v3` version
2. No live preedit was requested: doing so would require changing the user's
IME state or driving the focused native Wayland surface, neither of which this
investigation does.

Wayland text-input-v3 associates a text-input object with a seat and focused
surface. It requires clients to enable/disable on focus transitions and to
apply pending `preedit_string`, `commit_string`, and related updates only on
`done`. Text and offsets are UTF-8 byte data, with offsets at code-point
boundaries. It also permits cursor rectangles and, when known, bounded
surrounding text. GLFW 3.4 supports runtime selection between Wayland and X11
and exposes native Wayland display/surface access, but not this protocol in its
public input API.

## Decision

Retain GLFW as the window, event-loop, clipboard, HiDPI, and surface owner.
Do not replace it or create a separate Wayland display connection. Add a future
main-thread `platform.text_input` bridge only when its validation prerequisites
are met. It must be selected after `glfwGetPlatform()` confirms Wayland and use
the GLFW-owned `wl_display` and `wl_surface` through a small compiled bridge;
LuaJIT must not own Wayland listener layouts or dispatch a parallel event loop.

The portable internal boundary is an event sink rather than a window rewrite:

```text
platform backend -> focus / preedit / commit / done / leave
                               |
                               v
                    bounded composition state
                         |                 |
                    preedit overlay     committed UTF-8
                                              |
                           focused local query or existing PTY input path
```

`preedit` is transient renderer/input state: UTF-8 text plus byte-boundary
cursor range, capped before retention. It must not mutate terminal cells,
selection, scrollback, parser state, replay, clipboard, diagnostics, or the
PTY. `commit` is buffered and delivered only at `done` to the input owner that
is focused then. Existing local modes such as scrollback search receive the
committed text through their own text path; otherwise the normal terminal input
path receives the exact UTF-8 bytes. Focus loss, screen transition, and backend
failure clear preedit without emitting a partial commit.

The initial terminal integration deliberately sends no `set_surrounding_text`
or `delete_surrounding_text`: a terminal emulator does not know the shell or
full-screen application's editable buffer. It may provide a normal content
purpose and a cursor rectangle only. The bridge receives a logical content-cell
rectangle from the renderer/window boundary and is solely responsible for the
platform's surface-coordinate conversion; this prevents application code from
mixing framebuffer pixels, GLFW logical units, and Wayland surface units.

`src/kiwi/input/composition_spike.lua` is a detached executable prototype of
the `enter`, `preedit`, `commit`, `done`, and `leave` lifecycle. It bounds each
pending composition/commit to 1,024 bytes, rejects NUL, invalid UTF-8, and
mid-code-point ranges, applies no commit before `done`, and clears state on
leave. It has no window, Wayland, renderer, or PTY wiring and is not a claim of
IME support.

The production implementation boundary, if approved, is:

- `platform/window.lua`: owns backend construction/destruction and forwards
  focus/resize/content-scale changes.
- a compiled `platform/text_input_wayland` bridge: binds the advertised
  text-input manager on GLFW's display and safely converts protocol callbacks.
- `input/composition.lua`: promotes the spike to bounded portable state.
- app input dispatch plus a renderer-owned preedit overlay: routes commits and
  draws/clears composition without changing the terminal model.
- macOS `NSTextInputClient` and Windows TSF bridges: emit the same portable
  events; neither exposes native objects above the platform boundary.

## Rejected alternatives

- **Character callbacks alone:** retained for committed text, rejected as an
  IME solution because they expose no composition string, cursor range,
  focus lifecycle, or IME candidate rectangle.
- **Raw Wayland FFI in Lua:** rejected because generated protocol listener
  layout, callback lifetime, and display dispatch must remain ABI-safe and
  GLFW owns the event loop.
- **An SDL/GTK/Qt or new window-stack rewrite:** rejected for this milestone.
  It would replace the Vulkan-surface, clipboard, input, scaling, and future
  platform seams without evidence that it solves the portable IME boundary.
- **XIM/X11-only work:** rejected because the researched active session is
  Wayland and it would duplicate, rather than define, the cross-platform event
  contract.

## Consequences and follow-up decision

This is a research decision, not a production feature. No new window stack,
Wayland protocol dependency, preedit renderer pass, or user-visible IME option
is added. Existing GLFW character input remains unchanged.

An implementation follow-up is explicitly declined for now. The detached spike
is validated, but live IBus/Fcitx composition delivery, candidate placement at
integer and fractional scaling, focus handoff, compositor error handling, and
interaction with the native Wayland surface are unverified. Opening production
work before those tests would contradict the non-goal of claiming IME support
from a spike. Reconsider only when a focused Wayland test session can exercise
at least text-input-v3 preedit/commit/done/leave and when a macOS/Windows seam
owner has accepted the portable event contract.

## References

- [GLFW 3.4 release notes](https://www.glfw.org/docs/3.4/news.html)
- [GLFW input guide](https://www.glfw.org/docs/latest/input)
- [Wayland text-input-v3 protocol](https://wayland.app/protocols/text-input-unstable-v3)
