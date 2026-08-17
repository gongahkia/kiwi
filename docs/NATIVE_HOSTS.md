# Native host architecture

Kiwi's Ghostty-parity direction is native application chrome on macOS and
Linux, not a larger custom GLFW workspace. The current GLFW application remains
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
| macOS arm64 | AppKit | NSWindow/menus/tabs, NSTextInputClient, NSAccessibility, lifecycle and recovery | build, launch, IME, VoiceOver contract, tabs/splits, and release-bundle checks |
| Linux x86_64 | GTK4 | application/window integration, clipboard, input, session lifecycle, and drawing surface | **Feasibility only:** ABI build plus bounded Wayland/X11 WGPU/PTy rendering runs. Wayland presents through a host-owned child surface, so GTK retains its toplevel surface. Accessibility, IME, tabs/splits, and desktop qualification remain deferred. |

The terminal content may remain GPU-rendered. Native UI does not require a
native text widget or a replacement renderer.

## Migration sequence

1. The internal facade and host-owned WGPU-surface contract are implemented.
   GLFW remains the reference consumer.
2. GTK4 is an explicit development host selected with `KIWI_HOST=gtk` or
   `make gtk-run`. It owns `GtkApplication`/`GtkWindow`, event pumping, GDK
   Wayland/X11 surface discovery, title/resize/focus/input, bounded clipboard
   reads/writes,
   URI opening, and the existing GPU-rendered terminal content. `make
   gtk-host-check` validates its independent bridge ABI without a display.
3. The GTK Wayland rendering gate uses a WGPU-owned `wl_subsurface`, rather
   than sharing GTK's toplevel `wl_surface`; bounded single-window, framebuffer
   capture, and same-process multi-window runs pass on the Fedora/KWin session.
   Run `make gtk-wayland-smoke` and `make gtk-wayland-multi-window-smoke` from
   a Wayland session to repeat the first and third checks.
   Complete interactive desktop qualification before adding AppKit. Each later
   adapter owns its event loop and drawing surface; neither calls terminal-state
   internals.
4. Promote a host only after it passes the daily-driver corpus on its native
   platform. GLFW is then retained as a test/demo harness, not the product UI.

Windows remains out of scope until its existing ConPTY/DX12 feasibility matrix
has a real Windows host and a separate product decision.
