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
| Linux x86_64 | GTK4 | application/window/menu integration, GTK clipboard/accessibility, session lifecycle | build, Wayland/X11 launch, Orca/AT-SPI contract, tabs/splits, and desktop qualification |

The terminal content may remain GPU-rendered. Native UI does not require a
native text widget or a replacement renderer.

## Migration sequence

1. Extract an internal host facade from `app/main.lua`: create/destroy a
   session, route terminal input and resize, consume terminal effects, and
   request a frame. Preserve the current GLFW path as its first consumer.
2. Move workspace/window policy behind that facade. Session transfer and
   layout restoration remain model operations, while each host maps them to
   native windows, tabs, and split containers.
3. Add AppKit and GTK4 adapters one at a time. Each adapter owns its event loop
   integration and drawing surface; neither calls terminal-state internals.
4. Promote a host only after it passes the daily-driver corpus on its native
   platform. GLFW is then retained as a test/demo harness, not the product UI.

Windows remains out of scope until its existing ConPTY/DX12 feasibility matrix
has a real Windows host and a separate product decision.
