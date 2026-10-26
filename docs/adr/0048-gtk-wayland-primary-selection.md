# ADR 0048: Bounded GTK Wayland PRIMARY selection

## Decision

GTK's Wayland host uses GDK's primary clipboard on the existing display
connection. It reports support only when the compositor advertises a standard
or GTK primary-selection manager; GDK's local-only emulation does not establish
desktop support. X11 retains the existing bounded X selection converter,
including its INCR and legacy-text handling. GLFW/Wayland remains unsupported.

Both GTK WGPU and GTK GL use the same primary-selection input policy: publish
completed pointer/vi selections, explicit keyboard copy/paste, middle-button
paste with application mouse capture and Shift override, and Find-query routing.
Changing focus, pane, selection scope or input mode cancels delivery. Ordinary
CLIPBOARD ownership remains separate.

## Transfer and lifetime contract

`native/gtk_primary.c` requests a GDK input stream asynchronously, preferring
`text/plain;charset=utf-8` and accepting `text/plain` only when its bytes validate
as UTF-8. It reads at most 8 KiB per callback into a bounded buffer. One extra
byte distinguishes exact-limit EOF from excess data. NUL, malformed/truncated
UTF-8, over-limit data and errors produce no partial paste.

The limit is at most 1 MiB per request, sixteen live requests in the GTK native
module, and one second including stream acquisition and transfer. A GLib timeout
and monotonic deadline check both enforce expiry. No nested main loop or Lua
callback is needed by this reader. Ordinary clipboard reads are a separate path.

Caller ownership and in-flight native callback ownership are reference counted.
Destroying a requester cancels it and releases the caller reference; callbacks
retain their buffer and slot until completion. This permits safe window closure
without retaining a Lua window or terminal, and keeps detached requests within
the same capacity limit. It does not claim that all internal GDK allocations or
an external selection owner are bounded by Kiwi's transfer buffer.

The GTK host ABI is version 5 so an old bridge produces an explicit rebuild
error instead of a later missing-symbol failure.

## Wayland presentation prerequisite

The full application test exposed an existing first-presentation hang. Vulkan
was waiting in `wgpuSurfacePresent`/`wl_display_dispatch_queue` for a frame on an
unmapped subsurface. Creating and positioning a desynchronized subsurface still
changes double-buffered parent state. GTK could have finished painting its
unchanged parent before Kiwi created the child.

The bridge now commits the parent immediately after establishing the child
relationship, between GTK dispatches on the owning thread, before Vulkan can
wait for a child frame callback. The child continues to own its presentation
commits; this is not a recurring redraw timer or a second Wayland connection.

## Verification and limits

`make test-gtk-primary` covers exact/excess limits, multichunk UTF-8, invalid data,
capacity, cancellation before/after stream acquisition and a deliberately stalled
provider. AddressSanitizer and UndefinedBehaviorSanitizer pass. LeakSanitizer is
disabled for the GTK process; this is not a process-wide leak qualification.

`make gtk-primary-wayland-smoke` starts an isolated headless Sway compositor,
establishes a real keyboard focus/serial with wtype, and transfers data between
Kiwi and independent wl-copy/wl-paste clients. It then exercises real PTY paste
and the shared input policy on WGPU, GTK GL and native GTK tabs. All processes
and clipboard ownership belong to the fixture's private display. The temporary
requester floats so its creation does not resize the terminal during selection;
this test does not qualify resize behavior.

These checks run in Linux CI. Local evidence uses Ubuntu 24.04, GTK 4.14.5,
Sway 1.9 and software rendering. This establishes a compositor/protocol and
application integration result, not physical desktop, compositor-wide, screen
reader, IME, monitor-transition or suspend/resume qualification.

## References

- [GDK asynchronous clipboard streams](https://docs.gtk.org/gdk4/method.Clipboard.read_async.html)
- [Ownership of the returned stream](https://docs.gtk.org/gdk4/method.Clipboard.read_finish.html)
- [GIO asynchronous reads](https://docs.gtk.org/gio/method.InputStream.read_async.html)
- [Wayland registry capability queries](https://docs.gtk.org/gdk4-wayland/method.WaylandDisplay.query_registry.html)
- [Wayland subsurface parent-state rules](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_subcompositor)
