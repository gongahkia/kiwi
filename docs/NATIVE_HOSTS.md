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

## Target hosts

| Platform | Host | Native responsibilities | Initial acceptance gate |
| --- | --- | --- | --- |
| macOS arm64 | GLFW Cocoa with targeted AppKit bridges | GLFW owns the event loop, custom in-window tab/split workspace, and Metal surface. `Kiwi.app` runs that LuaJIT application in its own LaunchServices process. AppKit groups Kiwi's top-level windows into a native tab group and supplies a unified titlebar toolbar, global main menu, searchable command-palette panel, text-configuration opener, `NSTextInputClient`, pasteboard, `NSAccessibility`, current-layout key-variant bridges for Kitty flag 4, and a bounded Apple-event action bridge. | **Partial:** `make cocoa-smoke` covers bridge callbacks, Settings routing, AppKit window-tab grouping, unified toolbar dispatch, Cocoa/Metal surfaces, bundle launch, and the staged bundle's Apple-event action callback; `make cocoa-palette-smoke` opens the palette and dispatches `New Tab`. Interactive filtering/navigation, external automation permission, text-editor selection, tab switching/tearing-off, VoiceOver, IME, non-US physical-key behavior, and product chrome remain manual or unimplemented. |
| Linux x86_64 | GTK4 | `GtkApplication`/`GtkApplicationWindow`, window-scoped `GAction`/`GMenu` product actions, searchable command-palette dialog, text-configuration opener, clipboard, input, session lifecycle, accessibility projection, and drawing surface | **Partial:** bounded Wayland/X11 WGPU/PTy rendering, IME/accessibility callbacks, and product-menu callback paths are covered. `make gtk-palette-smoke` is the graphical-Linux palette gate. Interactive palette/menu behavior, desktop file-handler selection, IME, clipboard, fractional-scale, Orca, and desktop qualification remain manual. |

The terminal content may remain GPU-rendered. Native UI does not require a
native text widget or a replacement renderer.

## Migration sequence

1. The internal facade and host-owned WGPU-surface contract are implemented.
   GLFW remains the reference consumer.
2. The GLFW Cocoa route adds bounded AppKit bridges without becoming an AppKit
   host: its top-level GLFW windows join one `NSWindow` tab group while each
   retains its own WGPU surface, workspace, and PTYs; `NSMenu` items dispatch the same logical actions as the configured
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
   the same dispatcher; it is native titlebar chrome, not native ownership of
   the in-window workspace. `make cocoa-smoke` verifies the bridge structure
   and `make cocoa-menu-smoke` verifies a New Tab callback through the live
   controller. `make cocoa-palette-smoke` opens the palette and selects New
   Tab through the same controller. `make cocoa-automation-smoke` stages the
   bundle, validates the scripting definition, and dispatches `New Tab` through
   the live bundle process. `make cocoa-toolbar-smoke` dispatches the default
   toolbar New Tab item through the live controller. Those checks do not prove interactive filtering,
   every menu item, or an external automation client that has received macOS
   Automation permission.
3. GTK4 is an explicit development host selected with `KIWI_HOST=gtk` or
   `make gtk-run`. It owns `GtkApplication`/`GtkWindow`, event pumping, GDK
   Wayland/X11 surface discovery, title/resize/focus/input, bounded clipboard
   reads/writes, URI opening, and the existing GPU-rendered terminal content.
   It installs window-scoped `win.*` actions and a shared `GMenu`; the active
   `GtkApplicationWindow` dispatches the same host-neutral product-action
   dispatcher as the keyboard and Cocoa menu paths. GTK receives no hard-coded accelerators, so
   the bounded configured one- through three-chord key map remains the shortcut
   policy. `make
   gtk-host-check` validates its independent bridge ABI without a display;
   `make gtk-menu-smoke` needs a graphical Linux session to dispatch New Tab
   through that handler. Its searchable GTK dialog uses the same default and
   configuration-augmented bounded catalogue; `make gtk-palette-smoke` opens
   it and dispatches the first entry through the live controller on a graphical
   Linux session.
4. The GTK Wayland rendering gate uses a WGPU-owned `wl_subsurface`, rather
   than sharing GTK's toplevel `wl_surface`. It uses a private generated
   `wp_viewporter` binding to map each physical WGPU buffer to GTK's logical
   content size, keeping GTK responsible for fractional scale. GTK text input
   uses `GtkIMMulticontext` and preserves Kiwi's key/text correlation; its
   terminal widget implements `GtkAccessibleText` rather than starting a
   second AT-SPI application tree. Bounded single-window, same-process
   multi-window, input-callback, and accessible-text runs pass on the
   Fedora/KWin session. Run `make gtk-wayland-smoke`, `make
   gtk-wayland-multi-window-smoke`, `make gtk-input-smoke`, `make
   gtk-accessibility-smoke`, `make gtk-menu-smoke`, and `make
   gtk-palette-smoke` to repeat those checks.
   Real IME, public
   clipboard, scaled-monitor, and Orca qualification remains required before
   adding a full AppKit host. Each later adapter owns its event loop and drawing
   surface; neither calls terminal-state internals.
5. Promote a host only after it passes the daily-driver corpus on its native
   platform. GLFW is then retained as a test/demo harness, not the product UI.

Windows remains out of scope until its existing ConPTY/DX12 feasibility matrix
has a real Windows host and a separate product decision.
