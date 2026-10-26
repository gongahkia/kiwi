# GTK drawable pixels and allocation notifications

Status: implemented, 2026-10-26. Physical display qualification remains separate.

The terminal grid and font rasterizer use buffer pixels. GTK allocations,
pointer events and IME caret placement use logical coordinates. Each presentation
must report drawable dimensions as its logical content allocation multiplied by
its rendering scale, rounded to the nearest integer.

WGPU owns its Wayland buffer/viewport and uses
[`gdk_surface_get_scale`](https://docs.gtk.org/gdk4/method.Surface.get_scale.html),
including fractional values. GtkGLArea renders an integer-scaled framebuffer,
so that presenter uses the widget's integer scale for both font and drawable
pixels. Its fractional-desktop appearance is compositor-resampled; this is not
a claim that GL and WGPU use identical buffer resolutions.

Previously the presentation adapter returned logical drawable dimensions while
scaling the font, and always rounded the scale up to an integer. At desktop
scale 1.25, the failing regression reported a 1020×693 drawable with a 2× font,
only 46 columns and 16 rows. WGPU now reports scale 1.25 and a 1275×866 drawable
for that allocation, giving 91 columns and 32 rows with the test font. Exact cell
counts depend on the font's rasterized metrics.

GTK's terminal widget also subscribed to nonexistent `notify::width` and
`notify::height` properties. Its cached logical allocation consequently remained
at the initial request even when the compositor tiled or resized it. The widget
now implements GTK's
[`size_allocate` virtual method](https://docs.gtk.org/gtk4/vfunc.Widget.size_allocate.html)
and emits a local resize signal. This updates the existing Lua callback contract;
no native ABI change or production polling timer is introduced.

`make desktop-transition-smoke` runs WGPU and GL in a private D-Bus/Sway session
with two virtual outputs. It checks initial allocation, fractional scale, movement
to 2×, removal of the active output, return to the output, output power cycling,
a bounded process pause/resume and restoration to 1×. A real virtual keyboard
sends a fresh token through the application to a raw PTY child after each change.
The child reports its actual terminal dimensions. Success requires matching
child/model grid dimensions, font scale, logical allocation and pixel geometry,
plus successful WGPU presentation return or an acknowledged GL draw revision.

GDK may retain an oversampled buffer scale after an output is removed. The test
checks the compositor's actual destination output and consistency of pixel and
logical coordinates, rather than requiring that preferred buffer scale equal
the destination output scale at every instant. Both are retained in the report.

These tests exercise real GTK, compositor, renderer and PTY paths. They do not
establish physical hotplug, GPU-driver suspend recovery, system sleep, monitor
colour management, IME candidate placement at every scale or screen-reader
navigation. Output power commands and SIGSTOP/SIGCONT are explicitly identified
as limited recovery probes. Test instrumentation's 10 ms control-file polling
never enters production scheduling.
