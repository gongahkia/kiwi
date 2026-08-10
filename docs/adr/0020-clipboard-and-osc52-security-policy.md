# ADR 0020: clipboard and OSC 52 security policy

## Decision

The system clipboard is a user-owned boundary, not a terminal-output channel.

- Local **copy** is permitted only after an explicit Kiwi user action on a non-empty local selection. It copies at most 1,048,576 UTF-8 bytes atomically; a larger selection leaves the system clipboard unchanged.
- Local **paste** is permitted only after an explicit Kiwi user action. Kiwi reads at most 1,048,576 UTF-8 bytes from the system clipboard, rejects unavailable, NUL-containing bridge data, invalid UTF-8, or oversized data atomically, and sends no PTY bytes on rejection. It neither normalizes nor escapes accepted bytes. If bracketed-paste mode is active, it sends `CSI 200~`, the exact clipboard bytes, and `CSI 201~`; otherwise it sends only the exact bytes. The wrappers do not count toward the limit.
- Terminal-originated OSC 52 is denied by default. It cannot read the system clipboard, write or clear it, trigger a local paste, or produce a response. This applies equally to local programs, SSH sessions, multiplexers, logs, pagers, and replayed terminal output; Kiwi does not infer trust from the source.
- A later clipboard implementation may expose a static user configuration `clipboard.osc52` with only `deny` (default), `ask`, and `allow-write`. `ask` must require a focused, visible user decision for every valid write; `allow-write` is an explicit user opt-in for writes only. No configuration enables OSC 52 reads or query replies, grants persistent per-program trust, or enables primary/secondary selections or cut buffers.

The future OSC 52 write subset is deliberately narrow: `OSC 52 ; c ; Pd` terminated by BEL or ST, selector `c` only, strict RFC 4648 base64 `Pd`, non-empty decoded UTF-8 with no NUL, payload field at most 65,536 encoded bytes and at most 49,152 decoded bytes. Every other selector, query (`?`), malformed delimiter/base64/padding, invalid UTF-8, NUL, over-limit request, unavailable clipboard, denied prompt, or clipboard error has no clipboard side effect and no terminal response. A permitted request is all-or-nothing; decoded data is not retained after the platform call.

The current parser has a stricter 4,096-byte control-string cap. Until an implementation adds a streaming OSC 52 decoder, it remains the effective limit and all OSC 52 requests remain unsupported. Increasing the useful OSC 52 limit therefore requires bounded streaming decoding rather than increasing the generic control-string buffer.

## Rationale

Terminal output is frequently controlled by an untrusted remote process. Clipboard reads can exfiltrate secrets, while writes can replace a user’s next paste with attacker-controlled content. An explicit local copy/paste gesture has a clear user-intent boundary; terminal output does not.

OSC 52 conventionally carries a base64 selection write and may query selection data. XTerm describes both behaviors, including its `?` query form. Kiwi deliberately supports neither by default. GLFW supplies UTF-8 clipboard strings but requires clipboard calls on the main thread, so the eventual bridge belongs behind the window/input boundary rather than parser or renderer state.

The existing parser already bounds OSC storage and state records only the command number for unsupported OSC. The default-deny fixture preserves that property without adding a clipboard API or payload logging.

## Consequences

M4 selection and clipboard work preserve grapheme ownership when reconstructing selected text: continuation cells do not duplicate a cluster, and state normalization does not split a wide-cell anchor from its continuation. `Ctrl+Shift+C` copies only a visible non-empty selection through GLFW on the main thread. It uses stored glyph text rather than renderer substitutions, joins a soft-wrapped row to its successor, and otherwise inserts one LF between selected physical rows. `Ctrl+Shift+V` is the corresponding explicit local paste action. The platform bridge handles only the ordinary UTF-8 clipboard; primary selection, rich MIME data, and automatic clipboard synchronization are out of scope.

Diagnostics may count local copy/paste outcomes and OSC 52 allow/deny/invalid/over-limit results, but must never retain or print clipboard text, base64 payloads, or OSC content. Invalid configuration fails closed to `deny` and reports only the invalid setting name/value category. Prompt denial, parser rejection, and platform failure must not enqueue partial PTY data or emit an OSC reply.

The policy does not add a terminfo capability, environment advertisement, remote deployment claim, or a generic permission service. The implementation has deterministic selection/copy and paste framing, limit, unavailable, UTF-8, and NUL tests. A developer still needs a real focused Linux clipboard session to verify compositor behavior; unavailable bridges remain explicit no-PTY-write failures.

## References

- [XTerm Control Sequences: OSC 52 selection data](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [GLFW clipboard input and output](https://www.glfw.org/docs/latest/input)
- [Kitty clipboard protocol permission model](https://sw.kovidgoyal.net/kitty/clipboard/)
