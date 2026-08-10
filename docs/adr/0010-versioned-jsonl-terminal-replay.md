# ADR 0010: versioned JSONL terminal-kernel replay

## Decision

Record terminal-kernel resize, input, and PTY-output events as versioned JSON Lines with base64 byte payloads. Replay resize/output events headlessly into a fresh terminal state and produce canonical JSON snapshots.

## Rationale

Text JSONL is easy to inspect, sanitize, diff, and extend in M1. Recording at the kernel boundary makes parser/state failures reproducible without a live shell, PTY, GPU, or wall-clock timing.

## Consequences

Event and line sizes are bounded and unsupported versions are rejected. Input is retained for session evidence but state replay intentionally depends only on deterministic output and resize events. OSC 7/133 metadata, command regions, and row references derive again from those bytes rather than adding a separate persisted semantic event. Canonical snapshots are versioned observations, not JSONL input or a restore/archive format. A compact binary format and timed replay are deferred.
