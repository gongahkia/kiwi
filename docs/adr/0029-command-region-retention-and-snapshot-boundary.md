# ADR 0029: command-region retention and snapshot boundary

## Context

Command regions have stable row positions but originally no link to the row
objects that move through primary scrollback. Position-only records cannot say
whether a region remains represented in retained history after eviction,
resize, or alternate-screen operations.

## Decision

Each terminal row may retain a bounded ordered list of opaque command-region
IDs. Kiwi appends an ID when a region marker lands on the row or active-region
text writes to it. The list has at most eight IDs by default. A ninth distinct
ID does not displace an older reference: the row and new region are explicitly
marked truncated. No terminal text, URI, command, output copy, or renderer
handle is duplicated.

Region records count all tagged rows and currently retained tagged rows. Their
derived coverage is one of:

| Coverage | Meaning |
| --- | --- |
| `retained` | every tagged row still belongs to a primary/alternate screen or primary scrollback |
| `partial` | some, but not all, tagged rows remain |
| `evicted` | no tagged rows remain |
| `truncated` | at least one row exceeded the eight-ID reference bound |
| `none` | no row was ever tagged |

Rows continue to move by reference into primary scrollback. Ring replacement,
margin/delete/insert scrolling, reverse scrolling, scrollback clear, and resize
release or reconcile the affected opaque references. Region records never pin
rows or expand scrollback retention. A completed region can therefore remain as
bounded historical metadata with `partial` or `evicted` coverage; future
navigation must resolve a requested row ID at use time and report absence.

Canonical snapshots now carry `v: 1`, opaque per-visible-row ID lists/truncated
flags, and opaque region counters/coverage. A snapshot remains an observation
format only: Kiwi has no snapshot decoder or restore API. Its version is for
consumers to identify the shape; a consumer must reject an unsupported value
rather than attempt field inference. The existing v1 JSONL recording remains
the only replay input. It records resize/output bytes, derives row references
and regions through normal terminal state, and rejects an unsupported recording
version before mutation. No new persisted event type or migration is needed.

## Consequences

The retained terminal model has a small, inspectable association from history
rows to semantic regions without a history database or copied content. Visible
snapshots can expose only opaque identities to future local consumers, while
full historical reconstruction continues to come from replaying bounded input
records rather than importing a snapshot.

Tests cover scrollback survival followed by partial/fully evicted degradation,
resize reconciliation, same-row overflow, reset, visible snapshot shape, and a
recorded twelve-command stream whose replay snapshot matches direct parsing.
The design deliberately rejects unbounded row lists, preserving every region
forever, and treating canonical snapshots as a cross-version archive.

## References

- [ADR 0008](0008-row-indirection-and-bounded-scrollback.md)
- [ADR 0010](0010-versioned-jsonl-terminal-replay.md)
- [ADR 0028](0028-stable-command-region-lifecycle.md)
