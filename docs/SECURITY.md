# Security and Trust Boundaries

## 1. Scope

Stanczyk is not a security sandbox. It processes untrusted terminal streams and recordings, and it may optionally launch a real shell through a helper.

The security objective is to minimise accidental host integration, validate all external input, and state trust boundaries accurately.

## 2. Threat model

Potentially untrusted inputs:

- terminal output bytes from child processes;
- recording files;
- recording metadata;
- PTY helper messages;
- sandbox command arguments;
- effect configuration;
- third-party effect code;
- fonts and shaders loaded by the application.

Trusted components for v0.1:

- Stanczyk core code;
- installed PTY helper binary;
- explicitly enabled effect Lua code;
- host game code registering sandbox commands.

## 3. Recording threats

A malicious recording may attempt:

- oversized allocations;
- integer overflow;
- parser-state exhaustion;
- unterminated OSC or CSI strings;
- checksum bypass;
- deeply nested metadata;
- excessive checkpoint sizes;
- pathological output intended to consume CPU or memory.

Mitigations:

- strict payload bounds;
- bounded parser buffers;
- streaming processing;
- validated integer arithmetic;
- maximum dimensions and scrollback;
- maximum events per update;
- explicit corruption errors;
- no automatic execution of INPUT frames;
- no host actions from OSC sequences.

## 4. Terminal escape-sequence threats

Disable or treat as inert until explicitly designed:

- clipboard read/write;
- notification commands;
- file-transfer sequences;
- shell-integration commands;
- arbitrary hyperlink activation;
- host working-directory changes;
- palette changes with dangerous external effects;
- inline images with unbounded payloads.

Title changes may be accepted as bounded text metadata.

## 5. Sandbox mode

Sandbox mode must not expose host execution by default.

Prohibited default capabilities:

- `os.execute`;
- `io.popen`;
- arbitrary host filesystem access;
- dynamic native-library loading;
- network access;
- process spawning;
- environment-secret access.

Registered commands are trusted application code. The command context should expose only explicit capabilities.

The project must avoid describing this as secure execution of hostile Lua code.

`backend.sandbox` has no documented operation for `os.execute`, `io.popen`, host
`io.open`, process or PTY helpers, environment mutation, dynamic native loading, host
filesystem mounts, LÖVE system launch, or network access. Its built-ins use only the
per-session VFS facade and bounded output writer; its public `send_input(bytes)` never
injects host context into a handler. This is authority isolation for the documented API.
It does not stop malicious trusted Lua callbacks from reading global `os`, `io`,
`package`, or other globals available in the embedding process. Restricting hostile Lua
requires a separate restricted loading/runtime design.

## 6. Effect plugins

Effects run inside the LÖVE process and are trusted in v0.1.

Manifest capabilities improve clarity and validation but do not provide isolation.

The host should:

- validate configuration;
- catch runtime errors;
- disable failing effects;
- protect terminal semantic objects through read-only interfaces or copies;
- preserve the clean renderer;
- avoid loading effects automatically from untrusted recordings.

## 7. PTY helper

### 7.1 Protocol

- versioned handshake;
- bounded frames;
- exact message schemas;
- rejection of unknown critical commands;
- no command execution before successful handshake;
- raw terminal bytes isolated from control messages by framing;
- no unsafe deserialisation format.

### 7.2 Spawn policy

The standalone application may allow the user to configure a shell or command. It must not accept commands from recordings or effects without an explicit trusted action.

Spawn fields must be passed as executable plus argument array, not a shell-concatenated command string.

### 7.3 Lifecycle

The helper must:

- track the child it owns;
- handle parent disconnect;
- prevent accidental orphaning under the declared policy;
- avoid inheriting unintended file descriptors;
- report exit and errors precisely;
- avoid writing child output into logs.

## 8. Privacy

Terminal recordings may contain credentials, tokens, personal paths, source code, and private output.

Requirements:

- input recording can be disabled;
- metadata capture is allowlisted;
- recordings are not uploaded automatically;
- the app warns before sharing recordings that include input;
- no claim of password detection or reliable secret redaction;
- sample recordings contain no real secrets.

## 9. Denial of service controls

Configurable bounds should include:

- terminal columns and rows;
- scrollback rows;
- parser parameter count;
- CSI intermediate length;
- OSC payload length;
- recording metadata length;
- frame payload length;
- checkpoint size;
- queued backend bytes;
- events processed per update;
- glyph atlas pages;
- effect canvas dimensions and count.

Exceeding a bound must produce a defined result: ignore sequence, truncate metadata, disable effect, stop backend, or reject file. Silent memory growth is unacceptable.

## 10. Reporting

Before public release, add a security reporting address or issue policy. Do not invite vulnerability reports until there is a maintained process for receiving them.
