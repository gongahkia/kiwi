# ADR 0049: GTK input-method key ownership

## Decision

The GTK host offers each keyboard event to its input method before encoding
terminal input. Previously the capture controller sent Escape and Kitty key
reports before the input method could consume them. Real libpinyin composition
reproduced an Escape byte reaching the PTY while preedit remained active.

A capture-phase legacy event controller filters each press/release exactly once.
The existing IM-context controller retains GTK's focus handling. Its bubbling
filter never receives an event already consumed by the capture controller.
Unfiltered keys continue through the shared input policy. Synchronous plain-text
commits retain the physical key and its layout variants for associated-text
reporting; composed and asynchronous commits are independent Unicode text.
Consumed composition presses do not produce terminal release reports.

Some input modules dispatch a nested main loop during filtering. The bridge
retains subsequent native events in a FIFO, limited to 256 pending events,
and drains them after the current event finishes. This prevents a release from
overtaking its press or overwriting a synchronous commit buffer. The buffer is
limited to the existing 1,024-byte native text-input limit. Reported physical
keys are tracked separately, with a 256-key limit and reset on focus loss.
No new public callback or ABI version is needed.

GTK letter key identities are normalized to the shared GLFW-style uppercase
ASCII identifiers. The actual Unicode/layout/base/shifted scalars remain in the
variant tuple. This restores Ctrl-letter and product shortcuts without changing
their associated text.

When the native-tab container reparents its first terminal, or selects a page
that has not mapped yet, a pending focus request is fulfilled by that terminal's
map signal. Unselected pages clear the request. This preserves terminal focus
without removing keyboard access to the tab bar or scheduling a polling timer.

## Real-engine regression

`make gtk-ime-wayland-smoke` owns a private D-Bus session, temporary home/config,
headless Sway compositor, IBus daemon and libpinyin engine. A virtual keyboard
sends real Wayland key events. Kiwi runs its production controller and a raw
PTY child that records every received byte. Observers collect native preedit,
commit and raw-key callbacks; they do not inject composition callbacks.

Assertions cover Unicode commit, no preedit leakage, Escape cancellation,
Kitty flag-31 commit/release ownership, ordinary associated-text typing after
an engine switch, local Find composition/cancellation, Ctrl-C, and focus
loss/return. Each subprocess and handshake has a deadline; all owned processes
are terminated before the temporary environment is removed.

Ubuntu 24.04's IBus 1.5.29 client has an upstream GTK4 synchronous-mode bug:
hide-preedit replies are ignored with a `Type 'h' is not supported` warning.
The fixture leaves the default environment untouched and fails on that bug.
CI builds the pinned upstream 1.5.31 **client library only** into a private
prefix and supplies it to Kiwi through `KIWI_IME_CLIENT_LIBRARY`. The daemon,
GTK module and libpinyin remain distribution packages. A separate run uses the
stock library with `IBUS_ENABLE_SYNC_MODE=2` to exercise nested dispatch.
These are explicit qualification configurations, not application defaults or
a claim that unmodified Ubuntu 24.04 passes synchronous composition cancellation.

One engine on headless Wayland does not qualify physical input, candidate-window
placement, other compositors, Japanese/Korean/dead-key workflows, Cocoa IME,
screen readers, monitor transitions or suspend/resume.

## References

- [GTK input-method event filtering](https://docs.gtk.org/gtk4/method.IMContext.filter_keypress.html)
- [GTK controller IM filtering notification](https://docs.gtk.org/gtk4/signal.EventControllerKey.im-update.html)
- [IBus stale-preedit issue](https://github.com/ibus/ibus/issues/2596)
- [IBus 1.5.31 release](https://github.com/ibus/ibus/releases/tag/1.5.31)
- [Kitty keyboard protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
