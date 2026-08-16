# ADR 0028: stable command-region lifecycle

## Context

OSC 7/133 parsing supplies bounded terminal facts but does not define a
command's prompt, editable command, output, completion, or failure boundary.
Kiwi needs a derived lifecycle that stays deterministic through incomplete or
out-of-order cooperative-shell output, without scanning text or executing it.

## Decision

`terminal/command_regions.lua` derives opaque records only from accepted OSC
133 events. OSC 7 supplies the current-directory ID captured when a region
starts; it never supplies path text to a region. The model has one active
record and retains at most 256 records by default.

Each record has a monotonic local ID, start scope, current-directory ID, start
position, optional prompt/command/output/finish positions, optional 0–255 exit
status, state, and explicit recovery/interruption facts. Positions are
`{scope, line_id, column}` values over stable terminal rows. Records contain no
command/output text, URI, host, path, process ID, wall-clock time, or
renderer/native handle.

| Incoming marker | Active state | Result |
| --- | --- | --- |
| A | none | start `prompt` |
| B | `prompt` | enter `command` |
| C | `command` | enter `output` |
| D / D;status | prompt, command, or output | enter `completed`; retain status when present |
| B | none | start recovered `command` with `missing-prompt` |
| C | none | start recovered `output` with `missing-prompt-command` |
| C | `prompt` | enter `output` with `missing-command-start` |
| D | `prompt` or `command` | complete with an explicit missing-marker recovery |
| D | none | count as an orphan; retain only its raw marker record |
| A during an active region | any active state | interrupt the old region and start a prompt |
| B after output | `output` | interrupt the old region and start a recovered command |
| repeated B in command or C in output | matching active state | retain the region unchanged and count a repeat |
| marker in another screen scope | active region in another scope | interrupt the old region at its last same-scope position, then process the new marker normally |

RIS clears retained region data, active state, and local IDs/timestamps. It
does not alter cumulative diagnostics counters. Reaching the record bound drops
the oldest record and counts the drop. A region never pins a screen row or
scrollback entry: after ordinary screen changes or history eviction, an
unresolved stored row ID is historical metadata. Later navigation must resolve
it against retained rows and report absence rather than retain or reconstruct
text.

Canonical snapshots contain opaque region records and counters. Replay derives
the same IDs, transitions, and logical-event relationships from terminal bytes.
No `terminal.command_regions` renderer resource is added in ABI v1; a later
renderer issue must define a bounded descriptor, ownership, and invalidation
contract. This issue adds no navigation, persistence store, command execution,
shell setup, diagnostics payload, or UI.

## Consequences

The model makes lifecycle ownership explicit in terminal state while retaining
raw OSC facts for later policy. Region IDs are local to one terminal state and
stable only until RIS; paired with replay and stable row IDs, they are enough
for subsequent persistence and navigation work.

The implementation rejects text heuristics, unbounded event history, and
renderer-owned lifecycle inference. The deterministic suite covers ordinary
A/B/C/D, missing/out-of-order markers, repeats, scope changes, bounds, reset,
fixture chunking, and snapshot privacy. The noninteractive repository sample
exercises Kiwi's native PTY/parser/replay path; it does not certify a user's
bash, zsh, fish, or Nushell configuration. This environment's packaged defaults contain
no configured OSC 133 integration stream to capture without changing user
shell state.

## References

- [iTerm2 proprietary escape codes](https://iterm2.com/documentation-escape-codes.html)
- [Microsoft shell integration sequences](https://learn.microsoft.com/en-ca/windows/terminal/tutorials/shell-integration)
- [ADR 0027](0027-bounded-shell-integration-metadata.md)
