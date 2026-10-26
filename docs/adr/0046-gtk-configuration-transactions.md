# 0046: Transactional configuration for GTK GL pages

Status: accepted. The GTK GL presenter remains experimental.

The single-page GTK GL controller did not apply reload actions, and the
native-tab controller explicitly rejected them. Both now use a shared
configuration runtime for file dependencies, 200 ms debounce, opt-out/manual
reload, system-appearance changes and bounded recoverable errors. File
readiness and debounce deadlines participate in the normal event scheduler.
Failed loads retain missing-file dependencies so later creation can recover.

GTK pages own separate fonts and prepared-frame consumers. A reload plan stages
all pages before publishing any page: terminal state uses the same copy-on-write
transaction as WGPU, changed fonts are independently constructed, and each
replacement consumer continues its page's native revision sequence. Action maps
and host-effect policies are validated before publication. Failed construction
of a later page disposes all candidates and keeps every original page alive.
Equivalent settings, including comment-only edits, do not rebuild resources.

Atlas generations are local to a font cache. A supplied atlas update therefore
invalidates the native texture even when its generation and dimensions match
the previous font. Otherwise a valid configuration commit can retain old glyph
pixels. The native lifecycle fixture checks replacement pixels with an identical
generation using framebuffer readback.

Activation publishes existing state identities and new font/consumer references
without child I/O. Afterwards the plan publishes terminal effects, resizes PTYs
and disposes old consumers/fonts. Post-activation disposal/PTY resize errors are
reported; they are not represented as a rollback of an already active state.
GTK's GL driver resources and snapshot submission still follow its normal
presentation lifecycle; staging a consumer does not preallocate all future
driver allocations.

A hidden page without a drawable allocation keeps its existing grid and
resources until GTK assigns space. A new unallocated page starts at 80×24.
This avoids collapsing retained history to a 1×1 grid while reloading a tab
that is not selected. Selecting the page applies its actual geometry.

Both routes support automatic reload and default F6. Native-tab errors appear
in each page title; single-page errors appear in the window title. Unsupported
opacity/custom shaders and startup-only scrollback-limit/ambiguous-width
changes are rejected without modifying the current session. These capabilities
do not imply splits, recording, WGPU image passes or complete GTK GL parity.

Verification includes constructor failures on either of two pages, state and
resource identity checks, hidden-page geometry, debounce/opt-out/retry tests,
and an actual Xvfb/GTK GL fixture. The latter preserves running PTYs/history,
injects a failure in the last page's consumer construction, reloads with F6,
and reads the new palette from each selected page's framebuffer.
