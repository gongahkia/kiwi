# ADR-0006: Non-Reflowing Top-Left Resize Policy

- Status: Accepted
- Date: 2026-07-31

## Context

Terminal resize behaviour varies between emulators, especially for scrollback anchoring, wrapped-line reflow, inactive alternate-screen contents, margins, and tab stops. Stanczyk needs one deterministic policy for terminal semantics, recordings, checkpoints, and replay without claiming emulator-specific compatibility.

## Decision

`stanczyk-basic-v1` resizes the primary and alternate screens independently without reflow. Each resized screen retains its top-left intersection rectangle at unchanged coordinates. Cells right of a reduced width and rows below a reduced height are discarded. Expansion exposes canonical default blank cells. Discarded rows never enter scrollback.

Scrollback contents and ordering remain unchanged. The active and saved cursors are independently clamped to the new bounds and their pending-wrap flags are cleared. The scrolling region resets to the full resized screen, and tab stops are rebuilt at columns 9, 17, 25, and every eighth column thereafter. Existing modes, rendition, and parser and UTF-8 continuation state are preserved. Wide-cell pairs cut by a new right edge are replaced by canonical blanks.

Dimensions and derived per-screen cell counts are validated against terminal configuration bounds before screen allocation. Both replacement screens and cursor states are prepared before any terminal field is assigned, so a typed resize failure leaves semantic state unchanged. A same-size resize is a semantic no-op.

This policy is not an xterm, Ghostty, Kitty, or other emulator-specific resize claim. Bottom anchoring and line reflow require a separate versioned compatibility decision.

Checkpoint schema v2 records each scrollback row's own width so historical rows remain unchanged across a width resize. Schema v1 remains readable for recordings whose scrollback rows match the active width.

## Consequences

Positive:

- deterministic recording and replay;
- symmetric primary and alternate buffer handling;
- bounded allocation and no scrollback heuristics;
- checkpoints preserve the exact post-resize state.

Negative:

- shrinking permanently discards visible cells and rows;
- wrapped lines are not reflowed;
- behaviour differs from some terminal emulators.

## Rejected alternatives

### Bottom-anchored primary screen

Rejected because its asymmetric preservation rule introduces terminal-emulator-specific policy and complicates replay reasoning.

### Reflow wrapped lines

Rejected because it changes cell placement and scrollback semantics and needs a separate compatibility version.

### Clear screens on resize

Rejected because it unnecessarily loses preserved visible state.
