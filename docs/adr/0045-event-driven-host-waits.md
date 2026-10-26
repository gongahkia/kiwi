# 0045: Host waits follow readiness and explicit deadlines

Status: accepted for Linux/macOS; Windows remains deferred.

The live application previously woke every 50 ms (250 ms minimized), even
without terminal activity. Removing that timer requires covering work that
does not produce terminal output, as well as rendering deadlines.

Each window's one-shot readiness worker now watches up to 129 descriptors:
64 PTYs, 64 child-exit descriptors and a configuration descriptor. PTYs request
write readiness only while input remains buffered. Linux uses `pidfd_open`;
macOS uses a kqueue process filter with `NOTE_EXIT`. Both are close-on-exec.
Exit notification does not reap the child: the UI thread still calls `waitpid`
and closes the exit descriptor after reaping or shutdown. An exit watch remains
armed after terminal EOF. If creation fails (including an older Linux kernel
or a Darwin exit race), only that live child needs the former timed reaping
fallback. Worker failure wakes the host and is reported by the next update.

Linux GLFW also bridges default-context GLib sources to a readiness worker.
The UI thread owns the context across prepare/wait/dispatch, so cross-thread
source attachment can wake it. GLib timers shorten the host wait. Unsupported
poll interests, more than 65 GLib descriptors or unavailable context ownership
retain a 50 ms fallback. Callbacks run on the UI thread; workers only notify.
GTK waits directly on GLib, with `UINT32_MAX` denoting no timeout source.
Dispatch loops have iteration limits; one GLib iteration can still dispatch
multiple callbacks, so this is not a callback CPU-time bound.

The application requests an indefinite wait when no work is due. Pending
rendering/output is immediately runnable. Cursor/extension/effect animation,
development shader reload, configuration debounce, bounded navigation jobs,
primary-selection transfers, test runtime limits and device-soak actions have
explicit deadlines. Minimized/synchronized presentation defers rendering.
AppKit effective-appearance changes post a host event through the input view.
Native event pumps are excluded from JIT compilation because LuaJIT forbids
re-entering Lua callbacks from a compiled FFI call.

This removes the blanket application timer, not all toolkit/compositor wakes.
It does not establish energy savings, lower CPU usage or displayed latency.
The diagnostic demo's frame loop is separate from the live application policy.

Verification includes finite and indefinite host waits under an external
watchdog, output and buffered-input delivery, exit after EOF, native lifecycle
tests, quiet application gates and configuration/input regressions. The
configuration and primary-selection test drivers have their own explicit
deadlines instead of depending on a production polling interval.

References: [Linux pidfd semantics](https://man7.org/linux/man-pages/man2/pidfd_open.2.html),
[Apple kqueue semantics](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kqueue.2.html),
[GLib context ownership](https://docs.gtk.org/glib/struct.MainContext.html),
[LuaJIT callback restrictions](https://luajit.org/ext_ffi_semantics.html#callback).
