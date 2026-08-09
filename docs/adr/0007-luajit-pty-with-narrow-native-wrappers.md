# ADR 0007: LuaJIT PTY lifecycle with narrow native wrappers

## Decision

Use LuaJIT FFI for `forkpty`, `execvp`, read/write, waitpid, signals, and lifecycle policy. Keep only `TIOCSWINSZ` and nonblocking descriptor setup in the C bridge.

## Rationale

PTY policy belongs with Kiwi's application state and diagnostics. The C wrappers isolate ABI-sensitive ioctl/varargs details without moving process policy or terminal semantics out of LuaJIT.

## Consequences

The master is nonblocking and writes are explicitly queued. Shutdown sends HUP, TERM, then KILL if needed and reaps the child. Lua owns validation, default-shell selection, exit decoding, counters, and error handling.
