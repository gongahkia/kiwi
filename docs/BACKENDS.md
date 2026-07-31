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

### 6.5 Incremental output and backpressure

Each dispatched command owns a private byte FIFO. Its callback receives a writer as its
third argument and emits opaque Lua bytes with `writer:emit(bytes)`. Emit copies and
retains one entire logical chunk or none; it is non-blocking and never writes terminal
state, records, renders, or calls a host callback. Empty emits are no-ops.

Immutable defaults are 16,384 bytes per write, 65,536 queued bytes, 64 queued chunks,
16,384 drained bytes per poll, and 16 output events per poll. Hosts may lower these
bounds but cannot raise them; zero and negative limits are invalid. Exceeding either the
write or queue bound leaves the attempted bytes absent, latches `output_overflow`, and
closes the writer. An overlarge write itself reports `emit_too_large`; byte/chunk
capacity exhaustion reports `output_overflow`; later writes report `output_closed`.
Earlier queued output is preserved.

`invocation:poll({ max_bytes?, max_events? })` validates its requested limits before it
mutates the queue, drains its FIFO head, and may split only the head chunk to satisfy
`max_bytes`. API v1 deterministically coalesces the maximal permitted prefix into one
event, the fewest possible because no output channels exist. It returns
`runtime.event.output(bytes, 0, source_sequence)`: every event has `delta_us = 0` and a
stable monotonic sequence in host poll order. Polling neither dispatches commands nor
advances real or simulated time.

An invocation can finish or fail before its output drains. Its copied status exposes
execution state, queued bytes/chunks, typed failure, and settlement; it is settled only
once execution stops and the queue empties. Cancellation closes future writes, reports
`cancelled`, and preserves queued bytes for polling. Cleanup and final release are
idempotent. Only polled events reach terminal semantics or recordings. Blocking,
threads, implicit yielding, resumable producers, timed output, and inter-invocation
fairness are excluded from API v1. See ADR-0013.

Stable output reasons are `output_overflow`, `output_closed`, `emit_too_large`,
`invalid_poll_limit`, `output_resource_limit`, and `cancelled`. An
`output_resource_limit` failure leaves queue bytes unchanged.

### 6.6 Session-local history

Each sandbox session owns a separate in-memory FIFO history, never implicitly shared
with another session. It stores the exact submitted Lua byte string after strict
tokenization succeeds with at least one argument and before command lookup/dispatch.
Delimiter-only lines and tokenizer failures are absent; valid unknown commands,
execution failures, cancellations, duplicates, NUL, and invalid UTF-8 are retained
unchanged when within bounds.

Defaults are 128 entries, 32,768 total retained bytes, and 4,096 bytes per entry. Hosts
may lower but not raise them. A new entry evicts the minimum number of oldest entries
needed for entry-count and total-byte bounds. An oversized entry is not partially
retained and creates a typed history diagnostic without blocking its valid dispatch.
Setting both entry and total-byte capacity to zero disables history; other partial zero
capacities are invalid.

History uses one-based oldest-first `get`, bounded `list`, `length`, and idempotent
`clear`. It is cleared on session destruction and is lost when the session ends.
History is not terminal semantic state: it is not placed in recordings or checkpoints,
does not alter registered commands or active output invocations, and is not reconstructed
from recordings. See ADR-0014.

### 6.7 Completion scanner and registry names

Completion is synchronous, bounded, deterministic, and non-dispatching. It scans the
original byte line only through its zero-based cursor offset. The scanner follows the
Stanczyk sandbox command grammar but represents open single/double quotes and pending
unquoted/double escapes as state, allowing interactive incomplete input. Bytes after the
cursor never affect the decoded prefix. Invalid cursor offsets, oversized inputs, and
scan-resource bounds return typed errors without changing history, output, recordings,
terminal state, or registry state.

Registry command-name completion applies only within the first argument. It snapshots
the registry, uses exact byte-prefix matching, and returns names in bytewise ascending
order without fuzzy matching or locale collation. Candidates contain zero-based raw
replacement offsets and a copied insertion. API v1 replaces the whole active raw
argument with a project-owned canonical double-quoted encoding, escaping only backslash
and double quote under the Stanczyk grammar. This remains valid at token starts, middles,
ends, and incomplete quote contexts. Candidate count and byte limits validate atomically.

Completion does not invoke command handlers, emit output, access filesystem/environment
or processes, advance time, yield, or return a future. Command-specific callbacks are
documented separately. See ADR-0015.

When a later argument follows an exactly registered command, that command may declare a
validated synchronous `complete(request)` callback or the optional `completion`
capability. Its immutable request contains only command/argument byte data, cursor and
replacement offsets, quote state, and pending-escape state. It exposes no terminal,
output writer, registry, invocation, renderer, process, filesystem, environment, or
host callback. Callback order is preserved after atomic candidate validation; exact
duplicates are removed, while candidates with distinct metadata/ranges remain.

Callback candidates use logical byte values and optional bounded presentation/range
fields. The engine applies the canonical Stanczyk double-quote encoder and validates
candidate count, insertion/display bytes, total bytes, and replacement ranges before any
candidate is exposed. Stable callback failures are `unknown_completion_capability`,
`callback_failure`, `invalid_callback_return`, `too_many_candidates`,
`candidate_too_large`, `invalid_replacement_range`, and
`reentrant_completion_call`. Failures do not disable command handlers or mutate any
semantic/session state. See ADR-0016.

### 6.8 Session-local virtual filesystem

Every sandbox session owns one bounded, ephemeral in-memory filesystem. The optional
initial description is copied during session construction; it has one directory root
record, `{ kind = "directory", entries = { name = child, ... } }`, and children are
either that directory shape or `{ kind = "file", data = bytes }`. It never mounts or
retains host storage. It is isolated from every other session and is destroyed with its
session. Filesystem state is deliberately absent from terminal semantic recordings and
checkpoints; replaying terminal output does not reconstruct it.

The tree has only directories and opaque-byte regular files. Paths are byte-oriented:
`/` is the only separator, NUL is forbidden, and complete `.`/`..` components have
lexical navigation meaning. Repeated separators collapse, `..` clamps at the root,
and every successful resolution returns canonical absolute components. No UTF-8
normalisation, case folding, locale collation, host-path rules, tilde/environment/shell
expansion, links, mounts, permissions, timestamps, or executable semantics exist.
Non-root trailing slashes require a directory target.

The session stores cwd as a canonical absolute component sequence and logical directory
node. Relative paths resolve from that cwd. A directory rename updates a cwd held in
that directory or one of its descendants to its canonical new path without changing
the logical cwd node.

`fs:stat(path)`, `list(path, options?)`, `read_file(path, options?)`, `write_file(path,
bytes)`, `append_file(path, bytes)`, `make_directory(path)`, `remove(path)`,
`rename(source, destination)`, `get_cwd()`, and `change_directory(path)` return copied
values only. `list` returns immediate names in explicit ascending unsigned-byte order
and supports zero-based `offset` plus bounded `max_entries`; `read_file` supports
zero-based `offset` plus bounded `length`. Writes and appends are whole-operation
atomic. Append requires an existing regular file. Directory creation creates exactly
one node. Remove never recurses and rejects root, cwd, and cwd ancestors. Rename never
replaces an existing destination or moves a directory inside itself.

Immutable session limits bound input/canonical path bytes, component count/bytes,
nodes, directories, files, file and total bytes, directory entries, initial-tree depth,
and returned data. Hosts may only lower defaults. All limits are checked before an
allocation or mutation; a failed operation leaves the tree, cwd, and counters unchanged.
Stable errors are `empty_path`, `path_too_large`, `component_too_large`,
`too_many_components`, `invalid_path_byte`, `not_found`, `already_exists`,
`not_a_directory`, `is_a_directory`, `directory_not_empty`,
`root_operation_forbidden`, `cwd_operation_forbidden`, `invalid_move`,
`file_too_large`, `filesystem_full`, `directory_full`, `invalid_range`, and
`resource_limit`.

Filesystem access is command-capability gated. Session construction accepts copied
`granted_capabilities`; a command must declare and receive every required capability
before its handler begins. `vfs.read` provides `stat`, `list`, `read_file`, and
`get_cwd`; `vfs.write` provides `write_file`, `append_file`, `make_directory`,
`remove`, and `rename`; `vfs.chdir` provides `change_directory`. These are independent
grants. A qualifying handler receives only an expiring `context.fs` facade. Missing
grants fail with `capability_denied`; undeclared names fail registry validation with
`unsupported_capability`. Completion callbacks never receive filesystem access.

Host mounts, persistent/snapshotted filesystems, providers, shared namespaces, path
ACLs, recursive removal, and filesystem completion are excluded from API v1. See
ADR-0017.

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
