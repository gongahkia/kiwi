# ADR 0041: embedded GTK presentation before native Linux tabs

## Status

Accepted architecture; an experimental GtkGLArea presentation route is
implemented. Its `KIWI_GTK_NATIVE_TABS=1` prototype has a libadwaita
multi-page group: every page owns a distinct VT, PTY, Lua input state, GTK
terminal presentation, `GtkGLArea`, input/IME controller set, accessibility
node, font, and renderer state. The native menu/key dispatcher can create and
select those pages. It closes a non-final page by detaching its presentation
before releasing the session, and closes the final page by closing the group.
It deliberately rejects splits, session movement, detach/tear-off,
persistence, and the application manager's `host-tab` intent. The default GTK
host remains the toplevel-WGPU development host. Neither route advertises
GTK-native tabs before this ADR's acceptance gates pass.

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

To promote the experimental GTK native-tab route, retain a presentation adapter
with these
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
- libadwaita is an explicit GTK-host build, CI, and Linux release dependency
  for the experimental page owner. Product enablement still waits for the
  adapter's rendering, resize,
  scale, realization/unrealization, suspend/resume, and device-loss gates. The
  native container is an `AdwTabView` plus `AdwTabBar`, with libadwaita's
  conflicting global page-switching shortcuts disabled in favour of Kiwi's
  configured action map.
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

The checkpoint deliberately is not a generic renderer API: WGPU retains its
own pass preparation, GPU resources, Kitty-image composition, and encoder.
The experimental `GtkGLArea` OpenGL renderer consumes the extracted packed
prepared-frame model with its own snapshot, resource, and render callback
owners; it does not pass GTK handles through the terminal manager. The
compositor lifecycle remains WGPU-specific and is not evidence of native GTK
tabs or full renderer parity.

Focused lifecycle tests cover acquire/abort/present ownership, present failure,
and the WGPU queue command-buffer array ABI. Compositor tests cover opaque
frame ordering and abort-on-encode-failure. The live Cocoa smoke has exercised
the WGPU implementation through actual Metal resize and presentation. These
checks do not qualify the current GTK adapter or a Linux desktop.

### Prepared render-model boundary

The first producer slice is implemented as `kiwi.renderer.prepared_frame`.
It turns terminal damage, shaping, palette presentation, cursor/selection/
search/hyperlink/command-region overlays, glyph-atlas changes, and frame
uniform data into bounded LuaJIT buffers and descriptors. The WGPU renderer is
its first consumer: it uploads a plan, then explicitly acknowledges it before
terminal damage is cleared. If any upload fails, the producer retains terminal
damage and forces the next plan to be a complete cells/glyphs/atlas snapshot.
This makes stateful shaping and atlas insertion retryable without assuming a
specific GPU's partial uploads survived.

This is a versioned, internal render-model boundary, not a `backend` switch
scattered through `Renderer`. WGPU and OpenGL backends independently own GPU
allocation, upload, pipeline creation, and encoding. The producer may use
LuaJIT buffers for zero-copy backend uploads, but its data records contain no
WGPU, OpenGL, GDK, GTK, window, or controller handles.

The packed v1 part of that boundary is explicit in
`native/kiwi_render_model.h` and `kiwi.renderer.render_model`: native C and
LuaJIT assert the byte size and key field offsets for cells, shaped glyphs,
images, and frame uniforms. A future GL consumer must use this contract rather
than reproduce LuaJIT struct declarations locally. It is internal and may make
a coordinated breaking change while no stable native renderer ABI exists.

`kiwi.renderer.gtk_gl_consumer` is the matching Lua-side consumer. It submits
the prepared plan's bounded cell ranges plus changed glyph and atlas resources,
and clears terminal damage only after the native bridge accepts its deep copy.
The native side retains a bounded CPU mirror for the current grid and resource
generations. A native rejection leaves damage intact and forces the next plan
to restore every cell, glyph, and atlas resource. The module is tested with a
fake native window but is not yet selected by the application controller.

At minimum, a prepared frame has to carry:

- grid dimensions; dirty cell ranges and packed cell records; shaped-glyph
  ranges; glyph-atlas generation plus bounded pixel update data;
- terminal presentation values: cursor, selection, search, hyperlinks,
  command-region boundaries, time, and viewport/scissor intent;
- ordered semantic layers (`background`, images below text, overlays, glyphs,
  images above text, and cursor) with stable identifiers and blend/load intent;
- decoded Kitty image generations, pixels, bounded placement instances, and
  explicit release notifications; and
- a revision and ownership rule: an incomplete or superseded frame is dropped
  before a backend starts encoding, while a backend may retain only the newest
  successfully uploaded generation of each resource.

This is an internal application interface, not a v1 `libkiwi-vt` expansion.
The public terminal SDK continues to expose terminal-state render updates and
typed effects; it does not acquire fonts, GPU objects, presentation surfaces,
or host windows. A second non-Kiwi consumer remains the gate for widening it.

`kiwi.renderer.prepared_images` now selects decoded image generations, bounded
visible placement rows, active-image state, and release notifications without
returning a renderer or host handle. The WGPU-specific `KittyImages` owner is
its first consumer. Texture residency, texture release, bind groups, and
instance-buffer uploads remain WGPU-specific. An OpenGL adapter cannot
advertise Kitty-image compatibility until it consumes the same bounded decoded
generations and release rules. This is a data-boundary extraction, not evidence
of an OpenGL backend or complete backend-neutral image rendering.

### GTK execution and lifetime rules

The host supplies an opt-in lifecycle boundary with one `GtkGLArea` below each
accessible terminal root. It establishes the GTK-owned realize/render/unrealize
boundary, records context generations and render callbacks, and is structurally
checked by `make gtk-gl-area-smoke` in a real Linux graphical session. The
default presenter remains WGPU.

The GTK bridge now also builds a private OpenGL renderer against that ABI. Its
first executable stage accepts bounded resource updates and draws cell
backgrounds, selection/search ranges, alpha-atlas glyphs, and cursor geometry.
The probe submits a known RGB cell first in C and then a second complete
cell/glyph/atlas initialization through the LuaJIT FFI, requiring the GL
renderer to acknowledge each revision after a render callback.
`KIWI_GTK_PRESENTER=gl` selects `gtk_gl_controller`: without
`KIWI_GTK_NATIVE_TABS=1`, it is an experimental one-terminal application route
that drives this renderer from the real VT, PTY, shaping, keyboard, IME,
selection, clipboard, accessibility, and resize paths. With both variables,
an `AdwTabView` owns one complete terminal session per page. The GTK product
action bridge can create a second page through `New Tab` and select it through
`Next Tab`; each page has separate VT, PTY, input correlation, IME/accessibility
widget, font, prepared-frame consumer, and GL renderer state. Hidden sessions
continue to drain PTYs but do not advance a hidden GL presentation clock. The
prototype disables workspace restore/persistence and rejects splits,
session/window transfer, detach/tear-off, recording, and manager `host-tab`
requests. Its non-final close transaction detaches the page before it releases
the owning session; final-page close tears down the group. It is therefore an
integration boundary, not a partial claim for the remaining features.

Its OpenGL pass currently covers cell backgrounds; selection/search overlays;
atlas-backed shaped glyphs including the available text decorations; command
region separators; cursor; and the renderer-neutral primary-history scrollbar
overlay. GTK pointer handling gives that overlay track and thumb-drag ownership
before hyperlink, selection, or terminal mouse reporting. It does not consume
`prepared_images`, so Kitty images and animations are unavailable. It has no
colour-management or sRGB qualification, frame pacing/occlusion policy,
device-loss recovery, fractional-scale evidence, or graphical Linux result
yet. Command-region and hyperlink decorations have code paths but no
graphical-session evidence. The new Linux gates are `make gtk-gl-wayland-smoke`
and `make gtk-gl-x11-smoke`; they prove a bounded PTY-driven terminal reaches
the GtkGLArea render callback and that a one-cell update uses a bounded OpenGL
subrange upload, not visual quality or interactive desktop behaviour.

Each accepted native submission owns deep copies of its changed records. The
first submission for a grid, every grid-size change, and every retry is exactly
one complete cell update; later submissions may contain only dirty cell ranges.
The native adapter merges those ranges into its bounded CPU mirror and uploads
them with OpenGL subrange writes. Shaped glyph data is replaced only when its
producer marks it updated, while an unchanged atlas generation retains both the
native copy and OpenGL texture, including cursor-blink redraws. The renderer
still redraws the visible grid per GTK render callback. This removes the known
per-submission full-buffer upload, but is not a performance result: measured
Linux frame-time, pacing, colour, occlusion, and recovery evidence remain
required before it becomes the default GTK presenter.

The GL adapter uses that shape: one terminal root widget per controller, with
the `GtkGLArea` below that root. GTK's main context alone
creates, realizes, resizes, renders, unrealizes, and destroys the area. The
host event loop may prepare or mark a new scene while it handles PTY data, but
it must only request `gtk_gl_area_queue_render`; it must never issue OpenGL
calls outside GTK's realize/render/unrealize lifecycle or from another thread.

On realization the adapter makes the context current, checks GTK's context
error, and creates its GL resources. A render callback consumes at most the
newest accepted update set against GTK's current allocation; resize and scale
are therefore widget facts, not WGPU-subsurface policy. On unrealize or
device/context failure, the adapter releases only resources owned by that
realized GL context and reuploads its retained CPU mirror when it is recreated.
Page selection must queue the selected page only; it must not advance a hidden
terminal's presentation clock merely to keep a stale GL surface alive.

The group owner must avoid transiently destroying a page's presentation widget
to perform an ordinary select/reorder/layout update. Detach/tear-off is the
only operation allowed to create a new group presentation, and it needs a
defined rollback path that leaves the source page realized if target creation
fails. The acceptance gates below deliberately cover realize/unrealize and
detach failure as lifecycle behavior, rather than treating them as visual UI
details.

## Consequences

- On GTK's default WGPU route, `New Tab` remains a renderer-workspace tab. On
  the separately gated GL route, it creates an experimental independent
  libadwaita page. Neither behavior advertises the GTK `native_tabs` host
  capability yet.
- The current GTK bridge can continue to qualify window actions, IME,
  accessibility projection, clipboard, Wayland presentation, and PTY behavior
  independently of native tabs.
- Native GTK tabs remain a renderer and lifecycle project with a clear cost:
  full OpenGL pass/resource qualification plus a manager-owned page lifecycle.
  This is not a small C host change. A future documented WGPU/GDK interchange
  can be evaluated as a replacement only after it clears the same lifetime,
  backend, and benchmark gates.
- libadwaita is pinned as a current GTK build dependency (4.14+ GTK and 1.4+
  libadwaita) and appears in CI, Nix, and Linux release dependencies because
  the experimental native-tab path instantiates it; it is not merely unavailable
  decorative chrome.

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

`make gtk-gl-native-tabs-wayland-smoke` and
`make gtk-gl-native-tabs-x11-smoke` automate the first gate's New Tab path:
they dispatch the live GTK product action and require two distinct page/PTY
owners. Their `*-close-*` companions then dispatch Close Pane and require one
retained page/session. They do not exercise transfer, detach, or a Linux
desktop result in this checkout. Interactive GNOME/Wayland, X11, IME, Orca,
clipboard, and fractional-scale evidence remains a manual desktop qualification
requirement.

## References

- [Kiwi native host boundary](../NATIVE_HOSTS.md)
- [Ghostty GTK surface source](https://github.com/ghostty-org/ghostty/blob/main/src/apprt/gtk/class/surface.zig)
- [Ghostty GTK window source](https://github.com/ghostty-org/ghostty/blob/main/src/apprt/gtk/class/window.zig)
- [GTK `GtkGLArea`](https://docs.gtk.org/gtk4/class.GLArea.html)
- [GTK `GtkGLArea::render`](https://docs.gtk.org/gtk4/signal.GLArea.render.html)
- [libadwaita `AdwTabView`](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/class.TabView.html)
- [libadwaita `AdwTabBar`](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/class.TabBar.html)
- Pinned `wgpu-native v29.0.1.1` headers: `webgpu/webgpu.h` and `webgpu/wgpu.h`
