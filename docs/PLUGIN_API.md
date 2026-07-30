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

Conceptual hooks:

```lua
function effect:init(context, parameters) end
function effect:on_event(context, event) end
function effect:update(context, dt) end
function effect:transform_cell(context, visual_cell) end
function effect:draw_before(context) end
function effect:draw_after(context) end
function effect:post_process(context, input_canvas, output_canvas) end
function effect:resize(context, pixel_width, pixel_height) end
function effect:destroy(context) end
```

Hooks are optional and declared through capabilities.

### 4.2 Context

The effect context may expose:

- terminal and visual time;
- deterministic PRNG;
- read-only terminal queries;
- renderer metrics;
- bounded resource creation helpers;
- effect parameter access;
- logging;
- canvases approved for the current hook.

It must not expose mutable terminal internals.

### 4.3 Visual cell

A visual-cell object is a temporary rendering description:

```lua
{
  row = 1,
  column = 1,
  text = "A",
  x = 0,
  y = 0,
  scale_x = 1,
  scale_y = 1,
  rotation = 0,
  opacity = 1,
  foreground_multiplier = {1, 1, 1, 1},
  background_multiplier = {1, 1, 1, 1}
}
```

Effects may mutate this temporary object. Mutations do not feed back into terminal state.

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

Each plugin manifest declares `api_version`.

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
