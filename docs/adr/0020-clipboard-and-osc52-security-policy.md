# ADR 0020: clipboard and OSC 52 security policy

## Decision

The system clipboard is a user-owned boundary, not a terminal-output channel.

- Local **copy** is permitted only after an explicit Kiwi user action on a non-empty local selection. It copies at most 1,048,576 UTF-8 bytes atomically; a larger selection leaves the system clipboard unchanged.
- Local **paste** is permitted only after an explicit Kiwi user action. Kiwi reads at most 1,048,576 UTF-8 bytes from the system clipboard, rejects unavailable, NUL-containing bridge data, invalid UTF-8, or oversized data atomically, and sends no PTY bytes on rejection. It neither normalizes nor escapes accepted bytes. If bracketed-paste mode is active, it sends `CSI 200~`, the exact clipboard bytes, and `CSI 201~`; otherwise it sends only the exact bytes. The wrappers do not count toward the limit.
- Terminal-originated OSC 52 is denied by default. `osc52-write = true` permits an atomic validated write through the active platform clipboard bridge. `osc52-read = allow` separately permits a query reply, but is an explicit session-wide grant rather than a prompt, per-program rule, or source-trust decision. This applies equally to local programs, SSH sessions, multiplexers, logs, pagers, and replayed terminal output.
- OSC 52 accepts exactly one `c`, `p`, or `s` selector. Each is an alias for Kiwi's ordinary platform clipboard; this does not enable primary/secondary selections or cut buffers. A permitted `?` query emits only `{ selection, maximum_bytes }` to the host. The host reads at most 65,536 bytes, validates UTF-8 and NUL exclusion, then writes an ST-terminated base64 reply directly to its PTY. Terminal state, effects, diagnostics, and logs never receive the clipboard text or reply payload.

The OSC 52 write subset is deliberately narrow: `OSC 52 ; c|p|s ; Pd` terminated by BEL or ST, strict RFC 4648 base64 `Pd`, decoded UTF-8 with no NUL, and bounded terminal and platform payload limits. An empty `Pd` clear request is denied. A query uses exactly `Pd = ?`. When read permission is denied, the selector is malformed, the clipboard is unavailable, the data is invalid, or the data exceeds its limit, Kiwi emits no reply. A permitted request is all-or-nothing; decoded data is not retained after the platform call.

The parser's 4,096-byte control-string cap limits terminal-originated write payloads and query syntax. A permitted query reply has a separate 65,536-byte host-read limit. Increasing the useful write limit requires bounded streaming decoding rather than increasing the generic control-string buffer.

## Rationale

Terminal output is frequently controlled by an untrusted remote process. Clipboard reads can exfiltrate secrets, while writes can replace a user’s next paste with attacker-controlled content. An explicit local copy/paste gesture has a clear user-intent boundary; terminal output does not.

OSC 52 conventionally carries a base64 selection write and may query selection data. XTerm describes both behaviors, including its `?` query form. Kiwi supports neither by default. GLFW supplies UTF-8 clipboard strings on its main thread, while GTK supplies a bounded asynchronous clipboard operation behind a short nested main loop; both are host boundaries rather than parser or renderer state.

The existing parser already bounds OSC storage and state records only the command number for unsupported OSC. The default-deny fixture preserves that property without adding a clipboard API or payload logging.

## Consequences

M4 selection and clipboard work preserve grapheme ownership when reconstructing selected text: continuation cells do not duplicate a cluster, and state normalization does not split a wide-cell anchor from its continuation. `Ctrl+Shift+C` copies only a visible non-empty selection through GLFW on the main thread. It uses stored glyph text rather than renderer substitutions, joins a soft-wrapped row to its successor, and otherwise inserts one LF between selected physical rows. `Ctrl+Shift+V` is the corresponding explicit local paste action. The platform bridge handles only the ordinary UTF-8 clipboard; primary selection, rich MIME data, and automatic clipboard synchronization are out of scope.

Diagnostics may count local copy/paste outcomes and OSC 52 allow/deny/invalid/over-limit results, but must never retain or print clipboard text, base64 payloads, or OSC content. An invalid `osc52-read` setting is rejected rather than broadened; a reload keeps its prior configuration. There is no prompt implementation. Parser rejection and platform failure must not enqueue partial PTY data or emit an OSC reply.

The policy does not add a terminfo capability, environment advertisement, remote deployment claim, or a generic permission service. The implementation has deterministic selection/copy, paste framing, OSC 52 query, limit, unavailable, UTF-8, NUL, and public SDK tests. A developer still needs a real focused Linux clipboard session to verify compositor behavior; unavailable bridges remain explicit no-PTY-write failures.

## References

- [XTerm Control Sequences: OSC 52 selection data](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [GLFW clipboard input and output](https://www.glfw.org/docs/latest/input)
- [Kitty clipboard protocol permission model](https://sw.kovidgoyal.net/kitty/clipboard/)
