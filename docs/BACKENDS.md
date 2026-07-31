# Backend Design

## 1. Purpose

Backends are event sources. They do not own terminal semantics or rendering.

Every backend normalises its behaviour into the same event stream so that replay, sandbox, direct feeds, and PTY sessions exercise the same terminal core.

## 2. Common interface

Conceptual Lua interface:

```lua
local backend = Backend.new(config)
backend:start()
local events = backend:poll(now)
backend:send_input(bytes)
backend:resize(columns, rows, pixel_width, pixel_height)
backend:stop(reason)
local capabilities = backend:capabilities()
local status = backend:status()
```

Backends may reject unsupported methods with structured errors.

## 3. Event contract

Backends return ordered event tables with validated fields.

Example:

```lua
{
  kind = "output",
  data = "raw bytes",
  delta_us = 16000,
  source_sequence = 42
}
```

The coordinator assigns canonical ordering if a backend does not.

## 4. Replay backend

Responsibilities:

- read a recording stream;
- expose deterministic playhead time;
- return due frames;
- support pause, speed, seek, and step;
- restore checkpoints;
- surface corruption precisely;
- never execute recorded input.

The replay backend is the reference backend for deterministic tests.

Bootstrap control contract:

- `start()` begins playback at terminal time zero;
- `poll(advance_us)` advances only by its explicit microsecond argument, never host time;
- `pause()`, `play()`/`resume()`, `stop(reason)`, and `set_speed(multiplier)` control the replay state;
- `poll` processes at most the configured `max_events_per_poll` recording frames (default `1024`), retaining due frames for the next call;
- `step_frame()` pauses replay and returns exactly one decoded recording frame plus its normalised event, without mutating terminal state;
- seekable sources are indexed by bounded checkpoint offsets; `seek(target_terminal_us)` restores the nearest indexed checkpoint and leaves replay paused at the requested terminal time;
- seekable sources index bounded bookmark descriptors; `marks()` lists indexed mark names/times and `seek_mark(name, occurrence?)` resolves through the nearest checkpoint;
- INPUT frames remain informational events and are never sent to a host process.

## 5. Direct backend

A minimal direct-feed backend is useful for tests and embedding.

It allows a host application to enqueue:

- output bytes;
- resize events;
- marks;
- status events.

It must preserve queue order and avoid host callbacks during core mutation.

## 6. Sandbox backend

### 6.1 Purpose

The sandbox backend provides a command-oriented terminal environment without host process execution.

### 6.2 Components

- tokenizer;
- command registry;
- environment table;
- virtual working directory;
- virtual filesystem interface;
- history;
- completion;
- scheduled jobs;
- output emitter;
- host-domain event emitter.

### 6.3 Command contract

Conceptual registration:

```lua
terminal:register_command("unlock", {
  summary = "Unlock a game object",
  complete = function(context, partial) end,
  run = function(context, argv)
    context:write("Access granted.\r\n")
    context:emit("game.unlock", { id = "laboratory" })
    return 0
  end
})
```

Commands receive only declared capabilities. The default context does not expose `os.execute`, `io.popen`, arbitrary filesystem access, or native modules.

### 6.4 Syntax

Sandbox input uses the byte-oriented **Stanczyk sandbox command grammar** from
ADR-0012. It is not a POSIX shell parser or shell-compatible syntax.

The tokenizer consumes a bounded Lua byte string without decoding, normalising,
validating, or case-folding UTF-8. Only ASCII space (`0x20`) and horizontal tab
(`0x09`) delimit arguments while in the `unquoted` state; repeated, leading, and
trailing delimiters are ignored. No other byte is whitespace. Every input byte,
including NUL and invalid UTF-8, is otherwise opaque.

The state machine is:

- `unquoted`: ordinary bytes append to the active argument; backslash appends exactly
  the next byte; a single or double quote enters its quoted state; a delimiter ends an
  active argument.
- `single_quoted`: every byte is literal until a single quote closes the fragment.
  Backslash has no special meaning.
- `double_quoted`: ordinary bytes append literally; backslash appends exactly the next
  byte; a double quote closes the fragment.

Adjacent quoted and unquoted fragments concatenate. A quote begins an argument even
when its fragment is empty, so `""`, `''`, and `x""y` produce `""`, `""`, and `xy`
respectively. An unquoted or double-quoted trailing backslash is an error; an
unclosed quote is an error.

Default immutable upper bounds are 65,536 input bytes, 64 arguments, and 4,096 bytes
per argument. A caller may configure lower bounds only. Failures use
`sandbox_command_error` with `detail.reason`, a zero-based `detail.byte_offset`, and
`detail.state`. Stable grammar reasons are `unterminated_single_quote`,
`unterminated_double_quote`, `trailing_escape`, `input_too_large`,
`too_many_arguments`, and `argument_too_large`.

Tokenization succeeds before registry lookup or callback dispatch. Errors return no
partial argv and perform neither lookup nor dispatch. Delimiter-only input is a
successful no-op; otherwise `argv[1]` is the exact command-name byte string.

There is no variable, environment, command, arithmetic, tilde, pathname, brace,
alias, comment, redirection, pipeline, separator, background-job, control-operator,
subshell, here-document, or escape-sequence expansion. `$`, `*`, `?`, `|`, `>`, `<`,
`;`, `&`, `#`, parentheses, and backticks are ordinary bytes unless quoted or escaped.

## 7. PTY helper backend

### 7.1 Boundary

The LÖVE process launches an external helper executable. The helper owns:

- PTY creation;
- child process creation;
- platform-specific resize calls;
- reading and writing the PTY;
- child status collection;
- signal and termination handling.

The LÖVE process owns:

- helper discovery;
- version handshake;
- framed IPC;
- input event translation;
- terminal parsing;
- rendering;
- recording;
- user-visible errors.

### 7.2 Why an external helper

- keeps unsafe platform-specific code outside the graphics process;
- provides a clean crash boundary;
- simplifies platform packaging;
- makes the protocol independently testable;
- avoids exposing PTY implementation details to the terminal core;
- allows eventual helper replacement without changing recordings.

### 7.3 Helper commands

Initial LÖVE-to-helper messages:

- `hello` with protocol version;
- `spawn` with executable, argv, working directory, dimensions, and allowlisted environment;
- `input` with raw bytes;
- `resize`;
- `signal` where supported;
- `terminate`;
- `shutdown`.

Initial helper-to-LÖVE messages:

- `hello_ack`;
- `spawned`;
- `output`;
- `status`;
- `exit`;
- `error`;
- `shutdown_ack`.

### 7.4 Environment policy

The standalone app may inherit a curated environment required for normal shell behaviour. The helper protocol must support an explicit environment map rather than silently inheriting everything in tests.

Sensitive environment variables should not be copied into recording metadata.

### 7.5 Child lifecycle

Default policy:

- Stanczyk owns the spawned child;
- normal application shutdown requests graceful termination;
- after a bounded grace period, the helper performs platform-appropriate forced cleanup;
- helper crash is reported and the terminal becomes non-interactive;
- detach behaviour is deferred and must be explicit if added.

### 7.6 Backpressure

The helper and LÖVE adapter must handle output bursts without unbounded memory.

Potential policy:

- bounded IPC read buffer;
- bounded event queue;
- process a configurable byte/event budget per frame;
- continue draining helper output in a background thread or channel;
- surface overflow as an explicit fatal backend error rather than silently dropping bytes.

Exact limits require measurement and configuration.

## 8. Web and restricted platforms

Replay and sandbox backends should work without native PTY support.

The application should disable PTY options cleanly and explain why the backend is unavailable.

## 9. Backend testing

Every backend requires contract tests for:

- startup;
- ordered event delivery;
- input support or rejection;
- resize support or rejection;
- stop idempotency;
- status reporting;
- error propagation;
- capability accuracy.

PTY tests additionally cover helper protocol corruption, child exit, rapid resize, output bursts, and cleanup.
