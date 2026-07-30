# Codex Bootstrap Prompt

Use the following prompt when handing the repository to a fresh local Codex agent.

```text
Continue implementation of Stanczyk, a programmable terminal runtime and visual laboratory built with LÖVE.

Stanczyk is not a fake hacking terminal, browser engine, full shell, or daily-driver terminal replacement. Its core is a deterministic terminal state machine that consumes replay, sandbox, or PTY backend events. Rendering and effects are downstream, programmable, and unable to mutate terminal semantics.

Read the project documents in this exact order before changing code:

1. README.md
2. PRD.md
3. TODO.md
4. docs/ARCHITECTURE.md
5. docs/TERMINAL_COMPATIBILITY.md
6. docs/RECORDING_FORMAT.md
7. docs/RENDERER_AND_EFFECTS.md
8. docs/BACKENDS.md
9. docs/PLUGIN_API.md
10. docs/TESTING.md
11. docs/SECURITY.md
12. docs/RELEASE_CRITERIA.md
13. AGENTS.md
14. all accepted ADRs under docs/adr/

Then:

- inspect the worktree and existing tests;
- identify the earliest incomplete milestone in TODO.md;
- select the smallest coherent implementation slice within that milestone;
- state the slice, affected invariants, and validation plan;
- implement it without broadening scope;
- add or update tests;
- run the relevant checks;
- update TODO.md only for work actually completed;
- report files changed, tests run, milestone status, risks, and the next smallest safe slice.

Hard constraints:

- terminal, recording, and parser modules must be testable without love.*;
- backend input reaches terminal state only through declared events;
- effects and renderers cannot mutate terminal semantic state;
- sandbox mode must never execute host commands;
- replay and core state must use deterministic clocks and seeds;
- recording and IPC inputs are untrusted and must be bounds-checked;
- do not claim xterm compatibility beyond docs/TERMINAL_COMPATIBILITY.md;
- use the external PTY helper boundary described in ADR-0003;
- create an ADR before an irreversible format, protocol, or public-API change;
- do not recreate the project as a browser, fantasy computer, asset demo, or scripted mock terminal.

If the earliest slice is blocked by an irreversible decision not already accepted, do not guess. Present the decision, options, trade-offs, recommendation, and any unblocked preparatory work.
```
