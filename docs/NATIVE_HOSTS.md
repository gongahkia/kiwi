# Native host architecture

Kiwi's Ghostty-parity direction is native application chrome on macOS and
Linux, not a larger custom GLFW workspace. That is a direction, not a claim
that a full native host already exists. The current product route is still a
GLFW-owned window, event loop, workspace, and renderer. It has targeted Cocoa
bridges on macOS, while GTK4 is a separate, partial Linux host. GLFW remains
the reference renderer and development harness until each native host passes
the same terminal qualification gates.

## Boundary

`libkiwi-vt` remains the renderer-neutral terminal kernel. A native host owns
only platform policy: window/tab/split chrome, menus, shortcuts, clipboard,
IME, accessibility, launch/recovery, and the platform drawing surface. It must
not add platform handles, process state, or UI objects to terminal state.

The current public C API is not enough to replace the GLFW application: it
does not expose shaped text, GPU presentation, selection/search views, or a
PTY/session service. The first host work is therefore an internal host facade
over the existing application/session and renderer seams. The C API widens
only after a second real consumer requires a documented, testable capability.

### Host-tab contract

The application manager owns controller and session lifetime. Its private
`request_window(..., { kind = "host-tab", source_controller_id = ... })`
intent asks for a *new controller* to join the requesting controller's
host-native tab container; it does not move or clone the source terminal,
workspace, PTY, or renderer. `source_controller_id` is a manager-validated
identity, not a platform handle. A `{ kind = "standalone" }` request explicitly
opts out of host grouping. A host advertises `native_tabs` only when it both
creates that container and implements host-level tab selection. Hosts without
that capability continue to create tabs inside the renderer-owned `Workspace`.
The terminal kernel therefore never observes a native tab handle.

The GLFW/Cocoa host is the first consumer: it interprets `host-tab` as an
AppKit tab-group request. A normal `New Window`, restored window, and
move-to-new-window request are explicitly standalone. Cocoa's present group
implementation has one application group leader, but retaining the source
identity now avoids baking that shortcut into the application contract. A GTK
container must use it to find the group that owns the requested tab.

GTK does **not** advertise `native_tabs` yet. The opt-in GL route selected by
`KIWI_GTK_NATIVE_TABS=1` has an internal `AdwTabView` owner: `New Tab` creates
a distinct terminal session with its own VT, PTY, Lua input correlation state,
GTK input/IME controllers, accessibility projection, font, and `GtkGLArea`
renderer. `Next Tab` selects and focuses that page; background sessions
continue to drain their PTYs without advancing a hidden GL presentation clock.
The route is still an experiment, not the host-tab contract: it does not route
the application manager's `host-tab` intent, support splits, persistence,
session/window transfer, or detach/tear-off. It closes a non-final page by
first detaching its GTK presentation and then releasing that session; closing
the final page orderly closes the group. It has no graphical Linux result. The ordinary GTK controller still owns one
`GtkApplicationWindow` and one native content/surface owner. Merely adding a
`GtkNotebook` without replacing that per-controller toplevel ownership would
be cosmetic and would leave focus, close, teardown, session movement,
and surface ownership ambiguous. The current bridge derives its GDK surface
from that toplevel; on X11 it binds WGPU to the toplevel XID, while on Wayland
it creates a per-host `wl_subsurface`. A notebook cannot safely create multiple
current-style page renderers until a group explicitly owns a shared X11
presentation surface or supplies an equivalent per-page surface strategy on
both backends.

The GTK native-tab phase still needs a group-owner lifecycle above an embedded
GTK presentation adapter. The current WGPU surface is bound to the entire
toplevel: an X11 `Window` surface uses the toplevel XID, while the Wayland
route creates one `wl_subsurface` below that toplevel. GTK4 widgets do not
provide ordinary child-native surfaces, so putting the current renderer inside
a `GtkNotebook` would paint the wrong native region rather than create a page
surface. The group owner must therefore wait for a renderer that can present
inside a GTK widget on both X11 and Wayland.

The first renderer-side prerequisite is implemented: the compositor uses an
opaque acquire/encode/present-or-abort presentation-frame lifecycle rather than
acquiring and presenting a WGPU surface itself. Today that lifecycle is still
implemented solely by the WGPU context and the renderer accepts only WGPU
frames. It establishes explicit frame ownership and failure cleanup, but it
does not make the WGPU pass/resource pipeline backend-neutral. Its next core
layer, `prepared_frame`, produces bounded WGPU-free cells, shaped glyphs,
atlas updates, overlays, and uniform data, and clears terminal damage only
after a backend acknowledges the uploads. `prepared_images` also produces
renderer-neutral decoded Kitty image data and visible placements, but GPU
residency and all pass encoding remain WGPU-specific.

`KIWI_GTK_PRESENTER=gl` selects an experimental GtkGLArea route for one
PTY-backed terminal by default. Adding `KIWI_GTK_NATIVE_TABS=1` enables the
separately-gated multi-PTY `AdwTabView` prototype described above. Both use the
same VT, shaping, keyboard, GTK IME,
selection/clipboard, accessibility, and resize policies as the normal GTK
controller, then deep-copies bounded prepared updates into a private native
OpenGL renderer. Initial, resize, and retry submissions replace the complete
grid; ordinary terminal changes retain a bounded native mirror and upload only
dirty cell ranges and changed glyph/atlas resources. Background, selection/search, shaped alpha-atlas text,
available text decorations, command-region separators, and cursor passes are
implemented. Workspace restore/persistence, splits, session/window transfer,
recording, and Kitty images are not. The one-page GL route does not expose
product actions; the native-tab prototype exposes bounded New Tab, Next Tab,
and Close Pane actions through the same configured product-action dispatcher
but rejects split, movement, and persistence actions. It is deliberately
opt-in; `make gtk-gl-wayland-smoke`, `make gtk-gl-x11-smoke`,
`make gtk-gl-native-tabs-wayland-smoke`, and
`make gtk-gl-native-tabs-x11-smoke` are pending graphical Linux integration
gates. They do not qualify colour management, pacing, resize/scale behaviour,
device recovery, interactive IME, or visual comparison. [ADR
0041](adr/0041-embedded-gtk-presentation.md) records the remaining work.

The native-tab GL prototype uses
[libadwaita's `AdwTabView`](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/class.TabView.html)
and `AdwTabBar`, not `GtkNotebook`. `AdwTabView` is specifically designed for
dynamic multi-window document and terminal tabs, including reorder, detach,
transfer, and accessible tab panels. A production owner must resolve the request's
`source_controller_id`, attach/select/focus a controller page, transfer a
detached page to a standalone group, and remove a page before its controller
releases the embedded presentation resource. It must explicitly disable
libadwaita's built-in shortcut policy where it conflicts with Kiwi's configured
shortcut map. The current prototype proves distinct page/session/render
ownership and bounded New Tab/Next Tab/Close Pane dispatch, but not the
group-owner lifecycle or a supported GTK-native tab. [ADR
0041](adr/0041-embedded-gtk-presentation.md) defines the migration and
rejection criteria.

## Target hosts

| Platform | Host | Native responsibilities | Initial acceptance gate |
| --- | --- | --- | --- |
| macOS arm64 | GLFW Cocoa with targeted AppKit bridges | GLFW owns the event loop, per-tab split workspace, and Metal surface. `Kiwi.app` runs that LuaJIT application in its own LaunchServices process. AppKit owns the visible tab containers: `New Tab` creates another GLFW/Cocoa controller in Kiwi's explicit `NSWindow` group and `Next Tab` invokes AppKit selection. `New Window`, restored windows, and a move-to-new-window controller are registered outside that group; the verified GLFW/Cocoa default retains `NSWindowTabbingModeDisallowed` for them. AppKit also supplies a unified titlebar toolbar, local-shell `representedURL` proxy icon, global main menu, searchable command-palette panel, text-configuration opener, `NSTextInputClient`, pasteboard, `NSAccessibility`, current-layout key-variant bridges for Kitty flag 4, and a bounded Apple-event action bridge. | **Partial:** `make cocoa-smoke` covers bridge callbacks, direct AppKit grouping/next-tab selection and standalone-window configuration, Settings routing, unified toolbar dispatch, local/remote OSC 7 proxy-URL handling, Cocoa/Metal surfaces, and bundle launch. The menu, toolbar, palette, and Apple-event smokes each dispatch `New Tab` into the live host tab controller. Interactive filtering/navigation, Finder disclosure, external automation permission, text-editor selection, tab switching/tearing-off, VoiceOver, IME, non-US physical-key behavior, and product chrome remain manual or unimplemented. |
| Linux x86_64 | GTK4 4.14+ | `GtkApplication`/`GtkApplicationWindow`, window-scoped `GAction`/`GMenu` product actions, searchable command-palette window, text-configuration opener, clipboard, input, session lifecycle, accessibility projection, and either the default toplevel-WGPU surface or opt-in `GtkGLArea` surface. `KIWI_GTK_NATIVE_TABS=1` additionally selects an experimental libadwaita multi-PTY page owner. | **Partial:** the desktop workflow gates bounded Wayland/X11 WGPU/PTy rendering, IME/accessibility callbacks, and product-menu callback paths with distinct normal-presenter and widget-presenter commands. `make gtk-wayland-smoke` / `make gtk-x11-smoke` exercise the default WGPU route; their `*-multi-window-smoke` companions cover bounded same-process lifecycle; `make gtk-gl-wayland-smoke` / `make gtk-gl-x11-smoke` cover the one-terminal GL route. `make gtk-gl-native-tabs-wayland-smoke` / `make gtk-gl-native-tabs-x11-smoke` dispatch `New Tab` through the GTK product-action bridge and require separate page/PTY owners; their `*-close-*` companions dispatch `Close Pane` and require exactly one retained page/session. Per backend it also runs `gtk-input-*`, `gtk-menu-smoke`, `gtk-palette-smoke`, and `gtk-accessibility-smoke`. The default GTK route retains renderer-workspace tabs; the opt-in GL prototype has real `AdwTabView` pages, distinct per-page lifecycle, selection, and non-final-page close, but no manager `host-tab` lifecycle, splits, transfer, detach, persistence, or graphical Linux result. Interactive palette/menu behavior, desktop file-handler selection, IME, clipboard, fractional-scale, Orca, GL colour/pacing/recovery, and desktop qualification remain manual or unverified. |

A primary-screen wheel scrolls local history when application mouse tracking
is inactive on each current route. Kiwi still exposes no visible or native
scrollbar. A scrollbar must remain a host-presentation feature with a bounded
terminal viewport descriptor, pane-local pointer ownership, and native
accessibility semantics; it must not mutate the terminal protocol contract.

The terminal content may remain GPU-rendered. Native UI does not require a
native text widget or a replacement renderer.

## Migration sequence

1. The internal facade and host-owned WGPU-surface contract are implemented.
   GLFW remains the reference consumer.
2. The GLFW Cocoa route adds bounded AppKit bridges without becoming an AppKit
   host: `New Tab` starts a top-level GLFW/Cocoa controller in one explicit
   `NSWindow` group while each tab retains its own WGPU surface, split
   workspace, and PTYs. `New Window`, restored windows, and move-to-new-window
   controllers explicitly opt out of that group; `NSMenu` items dispatch the same logical actions as the configured
   local action map; a searchable `NSPanel` command palette dispatches the
   default and configuration-augmented bounded action catalogue;
   `NSTextInputClient`, private pasteboard, and
   `NSAccessibility` remain attached to the GLFW Cocoa view. `Kiwi.app` uses
   `native/macos_app_host.c` to load that same LuaJIT application in the bundle
   process; it no longer forks a separate terminal child. Its `Kiwi.sdef` and
   `NSAppleEventManager` bridge accept only eight bounded product actions:
   new window/tab, next tab, close pane, split right/down, reload configuration,
   and open configuration. They route through the same product-action dispatcher
   as menus, palette, and local keys. The bridge does **not** expose terminal
   text input, arbitrary action names, a Ghostty-style window/tab/terminal object
   model, or menu keyboard equivalents. A unified `NSToolbar` exposes fixed
   New Tab, Split Right, Split Down, Commands, and Settings controls through
   the same dispatcher. AppKit owns the tab containers, but not the split
   content inside one tab. The active session's accepted OSC 7 URI sets
   `NSWindow.representedURL` only for an empty, `localhost`, or current-host
   authority; remote or absent metadata clears it. Kiwi neither stats nor opens
   that URI. `make cocoa-smoke` verifies the bridge structure
   and `make cocoa-menu-smoke` verifies a New Tab callback through the live
   host tab controller. `make cocoa-palette-smoke` opens the palette and selects New
   Tab through the same controller. `make cocoa-automation-smoke` stages the
   bundle, validates the scripting definition, and dispatches `New Tab` through
   the live bundle process. `make cocoa-toolbar-smoke` dispatches the default
   toolbar New Tab item through the live controller. `make cocoa-cwd-smoke`
   feeds local then remote OSC 7 metadata through the live controller and
   verifies the native property assignment then clearing. Those checks do not prove interactive filtering,
   every menu item, or an external automation client that has received macOS
   Automation permission.
3. The compositor has a tested opaque presentation-frame lifecycle. Its current
   WGPU implementation owns acquire/abort/submit/present/release and has been
   live-smoked through Cocoa/Metal. `prepared_frame` separately emits core
   terminal/text/overlay buffers and retains damage until WGPU confirms their
   upload; Kitty image residency and all encoder calls remain WGPU-only. This
   is a prerequisite for a GTK widget renderer, not an embedded GTK renderer or
   native-tab implementation.
4. GTK4 4.14 or newer is an explicit partial Linux host selected with `KIWI_HOST=gtk` or
   `make gtk-run`. It owns `GtkApplication`/`GtkWindow`, event pumping, GDK
   Wayland/X11 surface discovery, title/resize/focus/input, bounded clipboard
   reads/writes, URI opening, and the existing GPU-rendered terminal content.
   It installs window-scoped `win.*` actions and a shared `GMenu`; the active
   `GtkApplicationWindow` dispatches the same host-neutral product-action
   dispatcher as the keyboard and Cocoa menu paths. GTK receives no hard-coded accelerators, so
   the bounded configured one- through three-chord key map remains the shortcut
   policy. `make gtk-host-check` validates its independent bridge ABI without a display;
   `make gtk-menu-smoke` needs a graphical Linux session to dispatch New Tab
   through that handler. Its searchable GTK dialog uses the same default and
   configuration-augmented bounded catalogue; `make gtk-palette-smoke` opens
   it and dispatches the first entry through the live controller on a graphical
   Linux session. Its default WGPU route does not advertise host-native tabs:
   `New Tab` remains a renderer-workspace tab. The separately gated
   `KIWI_GTK_NATIVE_TABS=1` GL route owns real libadwaita pages with independent
   terminal sessions, but does not yet implement the manager group-owner
   lifecycle or its attach/select/detach/close qualification.
5. The GTK Wayland rendering gate uses a WGPU-owned `wl_subsurface`, rather
   than sharing GTK's toplevel `wl_surface`. It uses a private generated
   `wp_viewporter` binding to map each physical WGPU buffer to GTK's logical
   content size, keeping GTK responsible for fractional scale. GTK text input
   uses `GtkIMMulticontext` and preserves Kiwi's key/text correlation. Its
   keyboard bridge carries the raw GDK keyval, a distinct Unicode scalar, and
   active-group level-zero/level-one plus standard-XKB-PC-101 variants for
   Kitty flag 4; custom XKB keycode remapping remains unqualified. The GTK
   host advertises flag 4 only after a live GDK keymap probe qualifies.
   Its
   terminal widget implements `GtkAccessibleText` rather than starting a
   second AT-SPI application tree. Optional text extents and hit testing are
   supplied on GTK 4.16 or newer; widget focus state is managed by GTK rather
   than calling the non-widget-only 4.18 platform-state API. Earlier bounded
   single-window, same-process multi-window, generic input-callback, and
   accessible-text runs passed on the Fedora/KWin session; they do not qualify
   the newer alternate-key path. Run `make gtk-wayland-smoke`, `make
   gtk-wayland-multi-window-smoke`, `make gtk-input-wayland-smoke`, `make
   gtk-input-x11-smoke`, `make
   gtk-accessibility-smoke`, `make gtk-menu-smoke`, and `make
   gtk-palette-smoke` to repeat those checks.
   Real IME, public
   clipboard, scaled-monitor, and Orca qualifications remain required before
   promoting GTK as a full native host. Each later adapter owns its event loop and drawing
   surface; neither calls terminal-state internals.
6. Promote a host only after it passes the daily-driver corpus on its native
   platform. GLFW is then retained as a test/demo harness, not the product UI.

Windows remains out of scope until its existing ConPTY/DX12 feasibility matrix
has a real Windows host and a separate product decision.
