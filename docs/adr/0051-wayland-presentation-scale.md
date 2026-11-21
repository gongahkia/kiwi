# Wayland WGPU presentation scale

Status: implemented, 2026-11-21. Physical monitor and system-sleep qualification
remain separate.

On the Omarchy laptop (GTK 4.24.1, Sway 1.12), the isolated output-transition
fixture reproduced a stale WGPU scale: after changing HEADLESS-1 from 1 to
1.25, the child accepted keyboard input and presented the new terminal grid,
but its drawable/font scale remained 1. GDK event diagnostics showed the
parent's initial preferred scale without a subsequent fractional-scale event.
The OpenGL route passed the same virtual-output sequence.

WGPU presents into a separate Wayland subsurface. That surface now owns an
optional `wp_fractional_scale_v1` listener and uses its preferred scale for
drawable pixels, font scaling, and resize callbacks. The listener and its
surface are destroyed together. Compositors without this protocol retain the
GDK scale fallback; X11 and GtkGLArea retain their existing scale paths.
Allocation or listener registration failure is reported before using the
presentation surface.

The protocol bindings are checked in, so building does not require a protocol
generator. Regenerate them with:

```sh
wayland-scanner client-header /usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml native/protocols/fractional-scale-v1-client-protocol.h
wayland-scanner private-code /usr/share/wayland-protocols/staging/fractional-scale/fractional-scale-v1.xml native/protocols/fractional-scale-v1-client-protocol.c
```

The existing transition fixture failed at the fractional checkpoint before
this change and passed afterward, including 1.25 and 2 scale factors, output
removal/return, output power cycling, process pause/resume, and restoration to
1. The fixture uses private Sway virtual outputs and software Vulkan. It
does not establish physical hotplug, hardware GPU suspend recovery, or system
sleep behavior.

The preferred-scale units and object lifecycle follow the
[Wayland fractional-scale protocol](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/fractional-scale/fractional-scale-v1.xml).
GDK's parent-surface behavior was inspected against
[GTK 4.24.1's Wayland implementation](https://github.com/GNOME/gtk/blob/4.24.1/gdk/wayland/gdksurface-wayland.c).
