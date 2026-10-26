# ADR 0043: X11 primary selection

Status: implemented for X11 pointer selection; actual-desktop qualification remains open.

## User and ownership contract

`primary-selection = true` is the default. On Linux X11, completing a local
left-button selection publishes an immutable UTF-8 snapshot to PRIMARY. Word and
line clicks publish on release. Empty, invalid or oversized selections leave the
previous primary snapshot intact. Ordinary clipboard copy/paste and OSC 52 keep
their existing policy; selecting text never overwrites CLIPBOARD. This increment
does not automatically publish vi selections or implement a keyboard paste-primary
action. Those keyboard conveniences remain open.

Middle-button press requests PRIMARY. With application mouse reporting active,
the application receives the button unless Shift invokes the configured
`mouse-shift-capture` override. Local presses own their corresponding release even
if the application's mouse mode changes. A fresh press replaces a lost release
claim. Vi, hints and Find input ownership take precedence over this pointer action.

The snapshot remains available through the native provider until another client
claims PRIMARY or the provider exits. Clearing the terminal highlight or disabling
new primary operations does not revoke an already-published snapshot. External
ownership loss does not erase the terminal's ordinary selection, and output does
not automatically reclaim PRIMARY. GLFW uses its display helper; GTK uses its
display's primary clipboard. Unsupported hosts return unavailable; GTK's local
emulation is deliberately not advertised as native primary-selection support.

## Bounded reads and lifetime

Readback uses a private X connection, UTF8_STRING with STRING fallback, and direct
or INCR transfers. Each poll handles at most 32 events and one 64 KiB property
slice. Accepted UTF-8 is limited to 1 MiB, including expansion of Latin-1 fallback.
Oversized data, malformed properties, NUL and invalid UTF-8 are rejected without
sending partial PTY input. A selection-owner response has a one-second deadline.
Connection setup and X server property/atom round trips still use synchronous
Xlib; this does not guarantee responsiveness to a hung X server.

The app loop polls only while work is pending. A target captures its State,
screen scope and bracketed-paste mode. Focus/pane changes, disabled policy or
entry into another product input mode cancels delivery. Accepted bytes pass
through the existing paste framing policy. There is one active conversion and
one replaceable latest queued target per controller, never an unbounded click
queue. Native read buffers are capped at 16 process-wide (at most 16 MiB).

Cancellation drains the already-requested conversion without delivering it.
Destroying a request window before the selection owner replies can cause an
owner's Xlib error handler to abort; this was reproduced with GLFW. Closing the
requesting Kiwi window therefore retires its conversion into a bounded process
pool, serviced by the remaining host event loop until completion/deadline. The
pool is included in the 16-read limit and does not keep an application running
after its last host exits. Other applications remain responsible for tolerating
requestors that disappear, as may happen when any process exits.

## Verification and boundaries

`make test-primary-selection` creates an isolated Xvfb server on Linux and tests
Unicode, Latin-1 conversion, 1 MiB INCR transfers, exact/over limits, malformed
responses, stalled owners, cancellation and clipboard isolation under native
sanitizers. On macOS it verifies the unavailable-platform contract.

`make primary-selection-smoke` uses a separate Xvfb server and a raw child PTY.
It exercises real native publication/readback, ordinary clipboard isolation,
middle/right button mapping, bracketed paste, application mouse routing, Shift,
replacement, focus cancellation and requester-window closure. Its clipboard
writes cannot touch the user's desktop. GLFW and all three GTK presentation
routes have separate executions; none establishes real Wayland/desktop behavior.

## References

- [X11 selection conventions and INCR](https://www.x.org/releases/X11R7.7/doc/xorg-docs/icccm/icccm.html)
- [GLFW native selection API](https://www.glfw.org/docs/latest/group__native.html)
- [GTK primary clipboard](https://docs.gtk.org/gdk4/method.Display.get_primary_clipboard.html)
