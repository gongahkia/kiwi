# ADR 0012: bounded PTY service turns

## Context

The M1 PTY reader drained until `EAGAIN` before returning to GLFW event polling. A continuously writable child could therefore make one outer-loop turn arbitrarily large, delaying input, terminal-generated responses, and rendering.

## Decision

`Pty:read_available` accepts an optional byte budget. The live app uses 4 KiB per service turn by default, configurable through `KIWI_PTY_READ_BUDGET`. The reader preserves ordering and returns the remaining bytes on later polls. The real-PTY burst harness enforces the same budget and checks a 250 ms maximum service-turn and 64 MiB retained-heap limit by default.

## Consequences

Bulk output is spread across more loop turns, favoring responsiveness over maximum single-turn throughput. No background reader, thread, queue, terminal library, or native parser is introduced. The headless harness measures scheduling opportunities rather than presented frames; native GPU presentation remains covered separately by `make smoke`.
