# Daily-driver regression corpus

Kiwi grows terminal compatibility from observed application failures, not from
an unbounded list of escape sequences. The compatibility ledger is the release
contract; this corpus defines the evidence required to change it.

## Baseline workloads

| Workload | Required behavior | Evidence |
| --- | --- | --- |
| Interactive shell | prompt lifecycle, Unicode input, resize, selection, clipboard | shell integration tests and native recording |
| tmux | nested TERM/colour contract and pane rendering | isolated tmux probe |
| Neovim and Vim | Kitty keyboard negotiation, mouse mode, alternate screen | bounded native recordings and replay |
| `top` or equivalent | dense full-screen redraw | bounded native recording and replay |
| SSH to a controlled host | private terminfo installation and conservative fallback | controlled remote probe |
| Unicode/image fixtures | grapheme width, fallback, PNG/APNG/GIF composition | deterministic fixtures plus native image checks |

`script/daily-driver-compatibility` is the automation entry point. Its
`--host glfw|gtk` option selects the desktop adapter for native workloads.
A successful native recording is replayed as captured, one output byte at a
time, and under eight deterministic randomized output chunk layouts; the final
screen, parser counters, unknown-control counters, and queued responses must
match. A skipped desktop or remote check is evidence of an unavailable
prerequisite, never a passing qualification.

## Change rule

For every application failure or requested protocol:

1. Capture the smallest sanitised byte stream or a deterministic reproducer.
2. Add a parser/state fixture that is invariant under arbitrary byte chunking.
3. Add PTY/input coverage when the behavior crosses the host boundary.
4. Run a native recording on every claimed platform when the behavior is
   visible, interactive, or renderer-dependent.
5. Update `docs/CONFORMANCE.md`, the compatibility manifest, and the
   daily-driver ledger with the exact scope and exclusion.

Terminfo changes are last. They require all of the above evidence plus a
review that the advertised capability matches the parser, terminal state,
input encoder, renderer, and host policy. A sequence that is merely accepted
is not sufficient reason to advertise it.
