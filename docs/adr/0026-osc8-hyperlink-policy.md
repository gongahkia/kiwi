# ADR 0026: bounded OSC 8 hyperlinks and explicit URI activation

## Decision

Kiwi implements the OSC 8 open form `OSC 8 ; params ; URI ST|BEL` and the
empty close form `OSC 8 ; ; ST|BEL`. The generic parser remains responsible
only for bounded OSC syntax; `terminal/hyperlink.lua` parses the OSC 8 payload
and `terminal/state.lua` owns the resulting cell metadata.

- A URI is at most 2,048 bytes, valid UTF-8, ASCII-only, NUL/control/space
  free, and has exactly one allowed scheme: `https`, `http`, or `mailto`.
  `file`, `data`, `javascript`, custom schemes, and malformed inputs are
  rejected.
- Parameters are at most 512 ASCII bytes of `key=value` fields separated by
  `:`. Kiwi recognizes optional `id` with a 128-byte value and otherwise
  validates then ignores parameter fields. A repeated `id` may reuse an
  existing target only when the URI is byte-identical; a different URI rejects
  the open. This preserves declared logical identity without allowing a later
  control sequence to retarget retained cells.
- An open replaces the current screen's active hyperlink. An empty close or a
  rejected open clears that current state. There is no nesting stack.
- At most 4,096 target records are retained per terminal lifetime. Once full,
  further new opens reject until RIS. The URI is retained only in terminal
  state, while each cell holds an opaque monotonically assigned identity.
- A hyperlink bit produces a colored underline through the glyph pass.
  `terminal.hyperlinks` is a read-only semantic resource containing only
  active state, a normalized color, and current visible-link cell count; it
  contains no URI, identity, terminal text, or native handle.
- Activation is local and explicit: `Ctrl+primary-click` opens a link under
  the pointer only while application mouse reporting is inactive, and
  `Ctrl+Shift+O` opens one under the visible cursor. Both actions are reserved
  before Kitty keyboard encoding and never enqueue PTY input.
- `input/hyperlink.lua` validates again at the user-intent boundary. The Linux
  bridge double-forks and calls `xdg-open` through `execlp` with the URI as one
  argv value; it performs no shell interpolation and redirects detached child
  standard streams to `/dev/null`. Successful launch only means the bridge
  spawned the opener, not that a desktop handler accepted or displayed it.

## Rationale

Terminal output can originate in remote hosts, pagers, logs, and compromised
programs. Rendering a link is therefore harmless metadata, but opening it is
a user-visible external action. A short allowlist plus a no-shell bridge keeps
the initial Linux interaction surface narrow. A bounded opaque record table
allows scrollback, resize, edits, and replay to preserve identity without
exposing targets to renderer extensions or diagnostics.

OSC 8 uses paired open/close sequences and optional IDs to connect related
text runs. Kiwi gives an ID identity only while its target remains unchanged;
it intentionally does not implement URI detection, hover previews, a browser
API, arbitrary schemes, or any automatic activation.

## Consequences

The terminal's flags include a hyperlink decoration bit while the target stays
out of the renderer-facing cell buffer. Resize and edit copies preserve both
the bit and opaque identity; fresh screen/scroll rows are unlinked, while an
erase or insertion follows the current terminal hyperlink state. Replay
reproduces OSC 8 output through the same parser/state path. Snapshots include
opaque cell IDs but not target strings.

The deterministic suite covers BEL/ST parsing, close behavior, malformed and
scheme rejection, matching/mismatched ID handling, URI/record bounds,
scrollback/resize/replay retention, pointer activation precedence, keyboard
reservation, and resource opacity. The native smoke verifies shader/pipeline
compilation. Manual verification remains required for focused compositor input
and the actual desktop's URI handler; it must not use an untrusted URI as a
test target.

## References

- [iTerm2: Hyperlinks in Terminal Emulators](https://iterm2.com/feature-reporting/Hyperlinks_in_Terminal_Emulators.html)
- [XTerm.js supported terminal sequences](https://xtermjs.org/docs/api/vtfeatures/)
- [XDG Utils](https://www.freedesktop.org/wiki/Software/xdg-utils/)
