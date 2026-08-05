# Release Criteria

## v0.1 definition

Stanczyk v0.1 is a credible developer release when it demonstrates the complete architecture across replay, sandbox, rendering, effects, debugger, and Unix PTY use.

It is not required to be a daily-driver terminal.

## Required product evidence

- Standalone application launches into a safe replay or sandbox example.
- User can open a recording, play, pause, seek, change speed, and step.
- User can switch between clean and built-in visual presets.
- User can inspect raw bytes, parsed sequences, and state changes.
- User can run a real shell on supported macOS and Linux configurations.
- User can record a PTY session and replay it without the helper.
- A separate LÖVE example embeds a sandbox terminal through public APIs.

## Required correctness evidence

- All supported compatibility fixtures pass.
- Chunk-boundary property tests pass across declared seeds and generated cases.
- Replay equivalence tests pass.
- Checkpoint equivalence tests pass.
- Recording corruption tests pass.
- PTY helper lifecycle and protocol tests pass.
- Effects do not change terminal state digests.
- Unsupported sequences are reported without corruption.

## Required performance evidence

Publish benchmark results for:

- clean renderer at 120×40;
- continuous plain output;
- colour-heavy output;
- alternate-screen updates;
- recording seek;
- CRT preset;
- kinetic preset;
- PTY output bursts.

Regressions against the recorded baseline must be understood or accepted explicitly.

## Required documentation

- installation;
- PTY helper setup;
- standalone controls;
- embedding API;
- effect API;
- recording format;
- compatibility table;
- known limitations;
- security and privacy boundaries;
- troubleshooting;
- licence and contribution process.

## Packaging

- Reproducible build instructions.
- Correct helper binary association per supported platform.
- Version handshake between app and helper.
- Sample recordings and built-in effects included.
- No dependency on local development paths.
- Clean start with no user configuration.

## Blocking defects

Do not release v0.1 with known defects that can:

- corrupt recording files silently;
- apply corrupt frames partially;
- orphan owned child processes under normal shutdown;
- execute host commands in sandbox mode;
- allow effects to mutate semantic state;
- crash on ordinary unsupported escape sequences;
- allocate unbounded memory from recording or IPC lengths;
- deadlock or freeze the render loop during normal PTY output;
- misrepresent the compatibility profile.

## Acceptable limitations

The first release may document:

- incomplete Unicode grapheme shaping;
- non-reflowing scrollback on resize;
- no Windows PTY support;
- no mouse tracking;
- no inline images;
- no clipboard OSC support;
- trusted in-process effects;
- limited selection and accessibility support;
- partial compatibility with complex TUIs.
