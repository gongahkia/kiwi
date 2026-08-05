# ADR-0003: External Native PTY Helper

- Status: Accepted for bootstrap
- Date: 2026-07-30

## Context

LÖVE does not provide the complete cross-platform PTY process interface needed for real interactive shells. Direct LuaJIT FFI would place platform-specific unsafe code and ABI assumptions inside the graphics process and complicate packaging.

## Decision

Implement PTY support through an external helper executable communicating over a versioned framed IPC protocol.

The bootstrap helper should be implemented in Rust unless a concrete build or portability blocker appears. The helper may use a focused PTY library but must keep the Stanczyk protocol independent of that library.

The LÖVE application remains responsible for parsing terminal bytes, rendering, recording, and user input translation.

## Consequences

Positive:

- clean crash and trust boundary;
- independently testable protocol;
- easier platform-specific process handling;
- no native library loaded into the LÖVE process;
- helper can evolve without changing terminal recordings.

Negative:

- additional build toolchain;
- packaging multiple binaries;
- IPC complexity and backpressure handling;
- version-handshake requirement.

## Rejected alternatives

### LuaJIT FFI directly to POSIX PTY APIs

Rejected for the initial implementation because it couples the application to OS ABI details and complicates Windows evolution.

### Shell process through ordinary pipes

Rejected because ordinary pipes do not provide terminal semantics required by interactive programs.

### Embed an existing full terminal emulator library

Rejected because implementing and testing the terminal state model is a central project goal.
