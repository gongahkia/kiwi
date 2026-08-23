# ADR 0041: embedded GTK presentation before native Linux tabs

## Status

Accepted architecture; first renderer boundary implemented. The current GTK
host remains a single-controller, toplevel-WGPU development host. It must not
advertise native tabs before this ADR's acceptance gates pass.

## Context

Kiwi's host-neutral tab request creates a new terminal controller and carries
the requesting controller's manager-validated ID. Cocoa can place each
controller in an `NSWindow` tab group because every controller keeps its own
top-level GLFW/Metal surface. The GTK host cannot use the same presentation
model.

`native/gtk_host.c` currently derives an X11 WGPU surface from the GTK
toplevel XID. On Wayland it creates one WGPU-owned `wl_subsurface` below that
toplevel and sizes it with `wp_viewporter`. GTK4 has no ordinary native child
surface for a `GtkNotebook` page. Nesting the existing controller content in a
notebook would therefore leave WGPU targeting the toplevel: on X11 it has no
page-sized native target, and on Wayland it has neither per-page lifetime nor
the required child position policy. A notebook would be visual chrome without
a valid renderer, focus, or teardown model.

Ghostty's GTK implementation takes the relevant architectural route: its
terminal surface is an embedded GTK widget with a `GtkGLArea`, and its GTK
window owns a libadwaita tab view. This is evidence that native Linux tabs sit
above an embedded rendering boundary, not evidence that Kiwi can reuse
Ghostty's implementation or API.

The pinned wgpu-native v29.0.1.1 C headers expose Xlib and Wayland *surface*
creation, but no texture import/export or GDK texture interchange API. Their
`WGPUExternalTexture` type is documented as a sampleable implementation-defined
YUV texture and has no public creation function. It cannot turn a Kiwi WGPU
render target into a GTK widget texture. A per-frame WGPU readback followed by
`GdkMemoryTexture` upload would work mechanically, but is intentionally not a
terminal presentation design because it adds a CPU copy and synchronization
point to every frame.

## Decision

Keep the existing top-level WGPU GTK host as the bounded development and
qualification host. Do not add `GtkNotebook` pages, fake native-tab capability,
or a GTK-specific terminal-state handle to it.

Before enabling GTK native tabs, introduce a presentation adapter with these
properties:

- GTK owns an embedded terminal widget per controller and its realized/unrealized
  lifecycle. The adapter presents Kiwi's existing semantic render-pass output
  into that widget on both Wayland and X11; terminal state, PTYs, and the public
  `libkiwi-vt` surface stay platform-neutral.
- It must not use WGPU texture readback followed by `GdkMemoryTexture` upload
  as the ordinary frame path. That adds a CPU copy and synchronization point
  to every terminal frame, which conflicts with Kiwi's performance baseline.
- The adapter will be a native OpenGL renderer owned by `GtkGLArea`. It must
  consume the same host-neutral terminal, text, image, and semantic pass data
  as the WGPU renderer, rather than putting GTK or OpenGL handles in those
  models. The current pinned WGPU C API cannot provide a zero-copy GTK
  interchange; reassess that alternative only after a pinned upstream API
  exposes documented texture sharing with lifetime and synchronization rules
  on both backends. A partial Wayland-only `wl_subsurface` solution is not.
- Only after that adapter passes its own rendering, resize, scale,
  realization/unrealization, suspend/resume, and device-loss gates may GTK
  add libadwaita as an explicit Linux-host dependency. The native container
  will be an `AdwTabView` plus `AdwTabBar`, with libadwaita's conflicting global
  page-switching shortcuts disabled in favour of Kiwi's configured action map.
- The group owner resolves `source_controller_id`; owns page attachment,
  selection/focus, reordering, close, and `create-window` detach; and destroys
  the embedded presentation resource before the controller or its renderer.
  A standalone request always creates a new group. No platform pointer crosses
  the Lua manager boundary.

`AdwTabView` is chosen over `GtkNotebook` because libadwaita documents it as a
dynamic multi-window document/terminal container and gives the group owner
page transfer and detach signals. It also supplies tab-panel accessibility. Its
default keyboard shortcuts are not Kiwi policy, so the owner must disable the
overlapping shortcuts rather than let two shortcut systems race.

### Implemented checkpoint

The first presentation boundary is now implemented, without changing the GTK
host or claiming an embedded renderer. `Compositor` obtains an opaque
presentation frame from its context, asks each renderer to encode into that
frame, then either presents or aborts the frame. The current `Context` owns
the WGPU acquire/configure/submit/present/release lifecycle; the current
`Renderer` explicitly accepts only `backend = "wgpu"` frames. This separates
host-window orchestration from WGPU surface ownership and makes resource
finalization explicit on both encode and present failures.

The checkpoint deliberately is not a generic renderer API: pass preparation,
GPU resources, glyph atlas, Kitty-image composition, and pass encoding still
use WGPU. A future `GtkGLArea` OpenGL adapter must consume a platform-neutral
prepared terminal/render model and implement its own frame type and encoder; it
must not emulate the current frame by passing GTK handles through the terminal
manager. The compositor lifecycle is a prerequisite for that extraction, not
evidence that an OpenGL GTK renderer or native GTK tabs exist.

Focused lifecycle tests cover acquire/abort/present ownership, present failure,
and the WGPU queue command-buffer array ABI. Compositor tests cover opaque
frame ordering and abort-on-encode-failure. The live Cocoa smoke has exercised
the WGPU implementation through actual Metal resize and presentation. These
checks do not qualify the later GTK adapter or a Linux desktop.

## Consequences

- `New Tab` remains a renderer-workspace tab on GTK. This is intentionally
  different from the Cocoa host-tab implementation and is not a regression
  claim.
- The current GTK bridge can continue to qualify window actions, IME,
  accessibility projection, clipboard, Wayland presentation, and PTY behavior
  independently of native tabs.
- Native GTK tabs become a renderer project with a clear cost: an OpenGL
  implementation of Kiwi's pass/resource pipeline. It is not a small C host
  change. A future documented WGPU/GDK interchange can be evaluated as a
  replacement only after it clears the same lifetime, backend, and benchmark
  gates.
- libadwaita is not added to current builds merely to display unavailable tab
  chrome. When the adapter is ready, the build contract must pin a supported
  libadwaita version and add it to CI and release dependencies.

## Acceptance gates

The GTK host may set `native_tabs = true` only after all of the following are
passed on actual Linux x86_64 graphical sessions, on both Wayland and X11:

1. A group attaches two independently live PTY/controller pages, selects next
   and previous pages, and returns focus/IME candidate geometry to the selected
   terminal only.
2. Closing a page releases exactly its renderer resources and sessions; closing
   the final page closes the group without leaks or a dangling action target.
3. Dragging a page to a new window transfers it atomically; rejecting or
   failing creation restores the source page unchanged.
4. Resize, fractional scale, minimize/restore, workspace changes, renderer
   device loss, and GTK widget realization/unrealization retain a usable
   selected terminal and do not present stale content.
5. GTK accessible text and product actions follow selected-page focus, and the
   configured Kiwi key map remains the only terminal shortcut policy.
6. Bounded rendering/pacing benchmarks are compared with the present GTK host;
   there is no mandatory per-frame CPU image round trip.

The automated portion needs dedicated attach/select/detach/close and
realization tests. Interactive GNOME/Wayland, X11, IME, Orca, clipboard, and
fractional-scale evidence remains a manual desktop qualification requirement.

## References

- [Kiwi native host boundary](../NATIVE_HOSTS.md)
- [Ghostty GTK surface source](https://github.com/ghostty-org/ghostty/blob/main/src/apprt/gtk/class/surface.zig)
- [Ghostty GTK window source](https://github.com/ghostty-org/ghostty/blob/main/src/apprt/gtk/class/window.zig)
- [libadwaita `AdwTabView`](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/class.TabView.html)
- [libadwaita `AdwTabBar`](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/class.TabBar.html)
- Pinned `wgpu-native v29.0.1.1` headers: `webgpu/webgpu.h` and `webgpu/wgpu.h`
