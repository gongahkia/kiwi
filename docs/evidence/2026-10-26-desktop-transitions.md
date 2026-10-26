# GTK desktop transitions, 2026-10-26

Implementation: `74b1b38`. Ubuntu 24.04 x86_64 container, GTK 4.14.5,
Sway 1.9, headless pixman compositor, llvmpipe rendering, private D-Bus/home/runtime.
The user's desktop and display configuration were not changed.

Both [WGPU](2026-10-26-transitions-wgpu.json) and
[GTK GL](2026-10-26-transitions-gl.json) passed eight checkpoints:

1. Initial mapped allocation at scale 1.
2. Change the first output to scale 1.25.
3. Move the terminal to the second output at scale 2.
4. Remove the active second output and observe migration to the first.
5. Restore the second output and move the terminal back.
6. Power the active output off, confirm its power state, then power it on.
7. Stop and continue only the owned application process.
8. Return to the first output at scale 1.

Each checkpoint includes a new token from a real Wayland virtual keyboard,
received by a raw PTY child and painted by the production renderer. Child terminal
size, model grid, font scale, drawable pixels and cached logical allocation must
agree. WGPU requires a successful present return; GL requires the submitted
revision to have reached the native draw callback. Neither establishes panel
scan-out timing or subjective visual quality.

The [pre-fix report](2026-10-26-transitions-before.json) retains the failing
fractional-scale checkpoint: input arrived, but WGPU rounded scale 1.25 to 2,
while returning unscaled drawable dimensions. The regression additionally found
that cached logical dimensions never received resize notifications. Both causes
and their coordinate contract are documented in
[ADR 0050](../adr/0050-gtk-drawable-scaling.md).

After the correction, native GTK build/ABI checks passed, as did existing X11
input, GL readback/lifecycle, configuration reload (single-page and native tabs),
and real Wayland IBus/libpinyin composition/cancellation/Find/focus/Kitty workflows.
The IBus run used the previously qualified private 1.5.31 client library; it does
not erase the documented stock-client dependency failure. Source checks passed.
The final transition reports identify archive revision `74b1b38`; archive working
tree cleanliness is explicitly unverified. CI now runs both transition presenters.

These are virtual-output and bounded process-recovery results. Physical display
hotplug, actual system suspend/resume, hardware GPU recovery, colour management,
screen-reader navigation and candidate placement across scales remain open.
The GTK GL prototype's other capability gaps are unchanged.
