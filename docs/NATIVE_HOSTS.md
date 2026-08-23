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

GTK does **not** advertise `native_tabs` yet. Today each GTK controller creates
its own `GtkApplicationWindow` and one native content/surface owner. Merely
adding a `GtkNotebook` without replacing that per-controller toplevel ownership
would be cosmetic and would leave focus, close, teardown, session movement,
and surface ownership ambiguous. The current bridge derives its GDK surface
from that toplevel; on X11 it binds WGPU to the toplevel XID, while on Wayland
it creates a per-host `wl_subsurface`. A notebook cannot safely create multiple
current-style page renderers until a group explicitly owns a shared X11
presentation surface or supplies an equivalent per-page surface strategy on
both backends.

The GTK native-tab phase must therefore introduce a group owner that resolves
the request's `source_controller_id`, defines the presentation-surface policy,
attaches a controller content surface as a notebook page, selects and focuses
the active controller, detaches a page into a new standalone group, and removes
the page before its controller releases the surface.
[GtkNotebook](https://docs.gtk.org/gtk4/class.Notebook.html) is the
appropriate GTK4 primitive: it owns tabbed child selection, supports page
reordering/detachment and a `create-window` signal, and supplies tab/list/page
accessibility roles. This is an implementation prerequisite, not a shipped GTK
feature.

## Target hosts

| Platform | Host | Native responsibilities | Initial acceptance gate |
| --- | --- | --- | --- |
| macOS arm64 | GLFW Cocoa with targeted AppKit bridges | GLFW owns the event loop, per-tab split workspace, and Metal surface. `Kiwi.app` runs that LuaJIT application in its own LaunchServices process. AppKit owns the visible tab containers: `New Tab` creates another GLFW/Cocoa controller in Kiwi's explicit `NSWindow` group and `Next Tab` invokes AppKit selection. `New Window`, restored windows, and a move-to-new-window controller are registered outside that group; the verified GLFW/Cocoa default retains `NSWindowTabbingModeDisallowed` for them. AppKit also supplies a unified titlebar toolbar, local-shell `representedURL` proxy icon, global main menu, searchable command-palette panel, text-configuration opener, `NSTextInputClient`, pasteboard, `NSAccessibility`, current-layout key-variant bridges for Kitty flag 4, and a bounded Apple-event action bridge. | **Partial:** `make cocoa-smoke` covers bridge callbacks, direct AppKit grouping/next-tab selection and standalone-window configuration, Settings routing, unified toolbar dispatch, local/remote OSC 7 proxy-URL handling, Cocoa/Metal surfaces, and bundle launch. The menu, toolbar, palette, and Apple-event smokes each dispatch `New Tab` into the live host tab controller. Interactive filtering/navigation, Finder disclosure, external automation permission, text-editor selection, tab switching/tearing-off, VoiceOver, IME, non-US physical-key behavior, and product chrome remain manual or unimplemented. |
| Linux x86_64 | GTK4 4.14+ | `GtkApplication`/`GtkApplicationWindow`, window-scoped `GAction`/`GMenu` product actions, searchable command-palette window, text-configuration opener, clipboard, input, session lifecycle, accessibility projection, and drawing surface | **Partial:** bounded Wayland/X11 WGPU/PTy rendering, IME/accessibility callbacks, and product-menu callback paths are covered. `New Tab` is still a renderer-workspace tab, not a GTK-native tab. `make gtk-palette-smoke` is the graphical-Linux palette gate. Interactive palette/menu behavior, desktop file-handler selection, IME, clipboard, fractional-scale, Orca, and desktop qualification remain manual. |

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
3. GTK4 4.14 or newer is an explicit development host selected with `KIWI_HOST=gtk` or
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
   Linux session. It does not advertise host-native tabs: `New Tab` remains a
   renderer-workspace tab until the GTK group-owner lifecycle described above
   exists and has its own attach/select/detach/close qualification.
4. The GTK Wayland rendering gate uses a WGPU-owned `wl_subsurface`, rather
   than sharing GTK's toplevel `wl_surface`. It uses a private generated
   `wp_viewporter` binding to map each physical WGPU buffer to GTK's logical
   content size, keeping GTK responsible for fractional scale. GTK text input
   uses `GtkIMMulticontext` and preserves Kiwi's key/text correlation; its
   terminal widget implements `GtkAccessibleText` rather than starting a
   second AT-SPI application tree. Optional text extents and hit testing are
   supplied on GTK 4.16 or newer; widget focus state is managed by GTK rather
   than calling the non-widget-only 4.18 platform-state API. Bounded single-window, same-process
   multi-window, input-callback, and accessible-text runs pass on the
   Fedora/KWin session. Run `make gtk-wayland-smoke`, `make
   gtk-wayland-multi-window-smoke`, `make gtk-input-smoke`, `make
   gtk-accessibility-smoke`, `make gtk-menu-smoke`, and `make
   gtk-palette-smoke` to repeat those checks.
   Real IME, public
   clipboard, scaled-monitor, and Orca qualifications remain required before
   promoting GTK as a full native host. Each later adapter owns its event loop and drawing
   surface; neither calls terminal-state internals.
5. Promote a host only after it passes the daily-driver corpus on its native
   platform. GLFW is then retained as a test/demo harness, not the product UI.

Windows remains out of scope until its existing ConPTY/DX12 feasibility matrix
has a real Windows host and a separate product decision.
