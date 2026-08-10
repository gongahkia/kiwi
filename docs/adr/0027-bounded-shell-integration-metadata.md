# ADR 0027: bounded OSC 7 and OSC 133 shell metadata

## Context

Cooperating shell integrations emit OSC 7 current-directory updates and OSC
133 prompt/command markers. They are advisory terminal output: a local shell,
SSH host, multiplexer, pager, or program may emit them. Kiwi needs stable,
replayable facts for later command-region work without treating that output as
a request to execute a command, access a path, or change normal terminal
behavior.

## Decision

`terminal/parser.lua` continues to recognize only bounded OSC syntax. It
passes OSC 7 and OSC 133 payloads to `terminal/state.lua`, which owns one
bounded `terminal/shell_integration.lua` model. The model is present whether
or not a shell emits integration sequences; absent metadata has no effect on
text, cursor, input, process handling, or presentation.

- OSC 7 accepts only an ASCII, valid-UTF-8, control/space/NUL-free `file://`
  URI of at most 2,048 bytes, with an optional host and an absolute path. It preserves
  the accepted URI as advisory current-directory metadata; it does not
  percent-decode, normalize, resolve, open, stat, display, or otherwise trust
  the host or path. Query and fragment components are rejected.
- OSC 133 accepts `A`, `B`, `C`, `D`, and `D;<0..255>`, terminated by BEL or
  ST. They become `prompt`, `command_start`, `command_executed`, and
  `command_finished` records; only the latter may carry an exit status. Each
  accepted sequence appends one record, including repeated markers. Malformed
  forms increment a bounded rejection counter; lettered unknown forms
  increment a separate unknown-marker counter. Neither form becomes an
  unknown generic OSC sample.
- Each record includes its active-screen scope, stable physical-row ID, cursor
  column, active current-directory ID, optional exit status, and a monotonic
  logical timestamp. The timestamp advances only for accepted shell metadata,
  so replay produces the same order without using wall time.
- Kiwi retains at most 128 directory records and 512 event records by default.
  Configuration may lower or raise those positive-integer limits for tests or
  callers. Oldest entries are dropped first and counted; a reset clears
  retained data and restarts local IDs/timestamps. Retained events may refer
  to an evicted directory ID rather than keeping a second unbounded path copy.
- Canonical snapshots contain only current-directory ID and opaque event data,
  never the directory URI, host, or path. No renderer resource, diagnostics,
  native bridge, input binding, shell setup script, or user interface exposes
  this metadata in this milestone.

## Consequences

The model gives later lifecycle work stable terminal anchors without parsing
arbitrary prompt text or imposing a shell integration requirement on ordinary
terminal sessions. A remote or malformed URI cannot cause local file access or
an external action because it remains terminal-state data only.

The deterministic fixture uses OSC 7 and the OSC 133 A/B/C/D sequence emitted
by common bash, zsh, and fish integrations, with both BEL and ST termination.
Unit tests cover rejected schemes/forms, unknown markers, repeated/bounded
records, reset, text non-mutation, and record/replay snapshot equivalence.
A native record/replay exercise may validate parser/state handling but is not
evidence that a particular shell's user configuration has installed or enabled
its integration script.

## References

- [iTerm2 proprietary escape codes](https://iterm2.com/documentation-escape-codes.html)
- [Microsoft shell integration sequences](https://learn.microsoft.com/en-ca/windows/terminal/tutorials/shell-integration)
- [Ghostty OSC 7](https://ghostty.org/docs/vt/osc/7)
