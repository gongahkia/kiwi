# Plugin and Embedding API

## 1. Scope

The initial plugin surface is for trusted Lua effects, render extensions, and sandbox commands. It is not a secure third-party sandbox.

The embedding API is the public interface used by other LÖVE applications.

These APIs are pre-stable until v0.1. Public changes must still be deliberate and documented.

## 2. Terminal instance API

Conceptual construction:

```lua
local stanczyk = require("stanczyk")

local terminal = stanczyk.new({
  columns = 80,
  rows = 24,
  backend = {
    kind = "sandbox"
  },
  renderer = {
    font = "assets/fonts/mono.ttf",
    font_size = 16
  },
  effects = {
    { id = "stanczyk.clean" }
  }
})
```

Required methods:

```lua
terminal:start()
terminal:update(dt)
terminal:draw(x, y, width, height)
terminal:resize(columns, rows, pixel_width, pixel_height)
terminal:send_input(bytes)
terminal:feed_output(bytes)
terminal:set_backend(config)
terminal:set_effects(effect_configs)
terminal:on(event_name, callback)
terminal:off(event_name, callback)
terminal:destroy()
```

The final names may change before implementation, but the responsibilities should remain.

## 3. Host events

Potential public events:

- `terminal.output`;
- `terminal.bell`;
- `terminal.cursor_moved`;
- `terminal.scrolled`;
- `terminal.resized`;
- `terminal.title_changed`;
- `terminal.unsupported_sequence`;
- `backend.status`;
- `backend.exit`;
- `sandbox.domain_event`;
- `effect.error`.

Callbacks must not run during an unsafe partial mutation. Prefer queueing and dispatching after the current backend event completes.

## 4. Effect API

### 4.1 Lifecycle

Lifecycle API v1 is defined by ADR-0008. Effects created through `effects.effect` provide a manifest and an optional hook table. The host calls a declared hook with the effect instance, fresh context, and hook argument:

```lua
local effect = Effect.new(manifest, {
  init = function(effect, context) end,
  on_event = function(effect, context, event) end,
  on_cell = function(effect, context, cell) end,
  before_canvas = function(effect, context, canvas) end,
  after_canvas = function(effect, context, canvas) end,
  update = function(effect, context, delta_us) end,
  shutdown = function(effect, context) end,
})
```

Hooks are optional. `lifecycle`, `terminal_events`, `cell_observation`, `canvas_before`, `canvas_after`, and `frame_update` respectively gate `init`/`shutdown`, `on_event`, `on_cell`, `before_canvas`, `after_canvas`, and `update`. A missing hook is a no-op; an undeclared hook fails loading. Effects run in manifest order.

### 4.2 Context

The fresh context contains only:

- effect ID and API version;
- optional session ID;
- frame sequence and integer elapsed microseconds;
- viewport and terminal dimensions;
- granted capability set;
- headless and canvas feature flags.

It contains no terminal, screen, parser, backend, renderer, process, filesystem, or unrestricted callback reference. A callback may mutate its own copy, but the mutation is discarded and cannot affect runtime state.

### 4.3 Visual cell

A visual-cell object is an immutable copied rendering description:

```lua
{
  row = 1,
  column = 1,
  text = "A",
  width = 1,
  foreground = "default",
  background = "default",
  attributes = 0,
  cursor = false,
  damage = true,
  screen = "primary",
  frame_sequence = 1,
}
```

The host invokes `on_cell` for caller-supplied, renderable visible cells in strict row-major order. Normal rendering supplies damaged cells; a full redraw supplies all renderable visible cells and marks each as damaged. The hook never receives a backing terminal cell.

### 4.4 Events and canvas

`on_event` receives `{ version, kind, sequence, timestamp_us, payload }`. Kinds and bounded payload schemas are defined by ADR-0008. Sequences and timestamps are monotonic; timestamps and `update` deltas are non-negative integer microseconds, never floating seconds.

Canvas hooks are unavailable in headless hosts. In graphical hosts they receive a narrow facade with dimensions, phase, and bounded `fill_rect`, `line`, and `text` operations. The host saves and restores graphics state around each callback and disables only an effect that fails.

## 5. Sandbox command API

Registration:

```lua
terminal:register_command("status", {
  summary = "Show system status",
  run = function(context, argv)
    context:write("All systems nominal.\r\n")
    return 0
  end
})
```

Command context may expose:

- `write(bytes_or_text)`;
- `write_line(text)`;
- `emit(name, payload)`;
- `schedule(delay_us, callback)`;
- `cwd()`;
- virtual filesystem operations granted to the command;
- environment lookups from the sandbox environment;
- deterministic random functions if granted.

Commands return a numeric or structured status.

## 6. Capabilities

Plugins and commands declare capabilities. Examples:

Effects:

- `terminal_events`;
- `cell_transform`;
- `row_transform`;
- `draw_before`;
- `draw_after`;
- `post_process`;
- `persistent_canvas`;
- `interactive_time`.

Sandbox commands:

- `virtual_fs_read`;
- `virtual_fs_write`;
- `domain_events`;
- `scheduled_jobs`;
- `deterministic_random`.

Capabilities document intent and allow validation; they are not a strong security sandbox in v0.1.

## 7. API versioning

Effect Manifest API v1 is defined by ADR-0007. It requires `id`, canonical stable SemVer `version`, integer `api_version = 1`, `determinism`, a dense duplicate-free `capabilities` array, and typed `parameters` with serialisable defaults. Supported determinism values are `static`, `deterministic`, and `interactive`. Unknown fields and unsupported versions are rejected before hooks load.

Policy:

- patch releases may add optional fields and hooks;
- incompatible hook or object changes require a new API version;
- the host rejects unsupported major API versions;
- adapters may support older versions when practical;
- public APIs must not depend on private module paths.

## 8. Resource lifecycle

Every object that allocates GPU or backend resources must have deterministic cleanup.

- `destroy()` is idempotent;
- effect unload releases canvases and shaders;
- terminal destruction stops owned backends;
- host application shutdown destroys all terminal instances;
- finalisers are not the primary cleanup mechanism.

## 9. Multiple instances

No module may assume one active terminal.

Per-instance state includes:

- terminal semantics;
- backend;
- renderer;
- effect chain;
- debugger state;
- callbacks;
- clocks;
- recording session.

Shared immutable assets or font caches may exist behind explicit managers, but instance behaviour cannot depend on global mutation order.
