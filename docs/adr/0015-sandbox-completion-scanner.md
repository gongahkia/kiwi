# ADR-0015: Sandboxed completion scanner and registry names

- Status: Accepted
- Date: 2026-07-31

## Context

Interactive completion must accept incomplete quotes and escapes without weakening the
strict command tokenizer or accidentally dispatching a command.

## Decision

Completion uses a separate bounded byte scanner. It consumes only the original line up
to its zero-based byte cursor. It follows the Stanczyk sandbox command grammar but
represents unfinished single/double quotes and trailing unquoted/double escapes as
scanner state rather than errors. Input, scanned arguments, scanned argument bytes, and
active-prefix bytes are bounded. Cursor offsets outside `0..#line` and all resource
failures are typed errors.

The scanner returns detached completed arguments, the decoded active prefix, active
argument start, cursor, quote mode, pending-escape flag, between-arguments flag, and
argument index. Bytes after the cursor do not contribute to the prefix. The completion
engine may inspect them only to identify the raw end of that argument's replacement
range.

API v1 completes registry command names only while the cursor is in the first argument.
It snapshots registry descriptors at the start of a call, matches exact byte prefixes,
and sorts names bytewise ascending. There is no locale collation, fuzzy matching,
dispatch, handler call, output, history admission, recording mutation, terminal access,
filesystem lookup, environment lookup, wall-clock input, future, or yield.

Candidates are copied records with zero-based `replace_start`/`replace_end`, canonical
double-quoted `insertion`, display, and bytewise sort key. The replacement range covers
the complete active raw argument so the same candidate is correct at the start, middle,
or end of a token. The project-owned encoder escapes only backslash and double quote,
which is sufficient inside this grammar's double-quoted fragments; it does not use POSIX
shell escaping or expansion. Candidate count, insertion/display bytes, and total
candidate bytes are validated atomically before a result is exposed.

## Consequences

Completion remains deterministic and side-effect free. Command-specific completion is a
separate extension layer; it must retain scanner bounds, candidate validation, and this
replacement/encoding model.
