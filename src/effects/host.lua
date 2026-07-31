local Errors = require("runtime.errors")
local Manifest = require("effects.manifest")
local Random = require("effects.random")

local Host = {}
local host_mt = {}
host_mt.__index = host_mt

Host.contract = {
  advance = "advance(delta_us) -> true | nil, error",
  before_canvas = "before_canvas() -> true | nil, error",
  after_canvas = "after_canvas() -> true | nil, error",
  constructor = "new(effects, options?) -> effect_host | nil, error",
  emit = "emit(kind, payload, timestamp_us) -> event | nil, error",
  limits = "limits() -> lifecycle_limits",
  observe_cells = "observe_cells(cells, full_redraw) -> true | nil, error",
  resize = "resize(viewport|nil, terminal, timestamp_us) -> event | nil, error",
  shutdown = "shutdown() -> true",
  status = "status() -> effect_host_status",
  update = "update(delta_us) -> true | nil, error",
}

local MAX_TIME_US = 9007199254740991

local hook_capabilities = {
  after_canvas = "canvas_after",
  before_canvas = "canvas_before",
  init = "lifecycle",
  on_cell = "cell_observation",
  on_event = "terminal_events",
  shutdown = "lifecycle",
  update = "frame_update",
}

local canvas_capabilities = { canvas_after = true, canvas_before = true }

local event_kinds = {
  bell = true,
  checkpoint_restored = true,
  cursor = true,
  damage = true,
  input = true,
  mode = true,
  output = true,
  replay_reset = true,
  replay_seek = true,
  resize = true,
  screen_switch = true,
  scroll = true,
  title = true,
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function incompatible(message, detail)
  return nil, Errors.new("effect_incompatible", message, detail)
end

local function runtime_error(message, detail)
  return nil, Errors.new("effect_runtime_error", message, detail)
end

local function bounded_integer(value, name, maximum)
  if
    type(value) ~= "number"
    or value ~= value
    or value % 1 ~= 0
    or value < 0
    or value > maximum
  then
    return config_error(name .. " must be a bounded non-negative integer", { provided = value })
  end
  return value
end

local function positive_integer(value, name, maximum)
  local valid, valid_error = bounded_integer(value, name, maximum)
  if not valid or valid == 0 then
    return nil, valid_error or Errors.new("config_error", name .. " must be positive")
  end
  return valid
end

local function bounded_string(value, name, maximum)
  if type(value) ~= "string" or #value > maximum then
    return config_error(name .. " must be a bounded string", { provided = value })
  end
  return value
end

local function dense_array(value, name)
  if type(value) ~= "table" then
    return config_error(name .. " must be an array")
  end
  local length = #value
  for key in pairs(value) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
      return config_error(name .. " must be a dense array")
    end
  end
  return length
end

local function exact_fields(value, fields, name)
  if type(value) ~= "table" then
    return config_error(name .. " must be a table")
  end
  for field in pairs(value) do
    if not fields[field] then
      return config_error(name .. " contains an unsupported field", { field = field })
    end
  end
  return value
end

local function dimensions(value, names, name)
  local accepted, accepted_error = exact_fields(value, names, name)
  if not accepted then
    return nil, accepted_error
  end
  local result = {}
  for field in pairs(names) do
    local valid, valid_error = positive_integer(value[field], name .. " " .. field, 0xFFFFFFFF)
    if not valid then
      return nil, valid_error
    end
    result[field] = valid
  end
  return result
end

local function colour(value, name)
  if value == "default" then
    return "default"
  end
  local accepted, accepted_error =
    exact_fields(value, { blue = true, green = true, index = true, kind = true, red = true }, name)
  if not accepted then
    return nil, accepted_error
  end
  if value.kind == "indexed" then
    local index, index_error = bounded_integer(value.index, name .. " index", 255)
    if not index then
      return nil, index_error
    end
    return { index = index, kind = "indexed" }
  end
  if value.kind ~= "rgb" then
    return config_error(name .. " kind is unsupported")
  end
  local copy = { kind = "rgb" }
  for _, field in ipairs({ "red", "green", "blue" }) do
    local component, component_error = bounded_integer(value[field], name .. " " .. field, 255)
    if not component then
      return nil, component_error
    end
    copy[field] = component
  end
  return copy
end

local function context_for(host, entry)
  local capabilities = {}
  for _, capability in ipairs(entry.manifest.capabilities) do
    capabilities[capability] = true
  end
  local context = {
    api_version = Manifest.api_version,
    capabilities = capabilities,
    effect_id = entry.manifest.id,
    elapsed_us = host.elapsed_us,
    frame_sequence = host.frame_sequence,
    runtime = {
      canvas = host.canvas_runtime ~= nil,
      headless = host.headless,
    },
    session_id = host.session_id,
    terminal = { columns = host.terminal.columns, rows = host.terminal.rows },
    viewport = { height = host.viewport.height, width = host.viewport.width },
  }
  if entry.random then
    local random = entry.random
    context.random = {
      integer = function(_, minimum, maximum)
        return random:integer(minimum, maximum)
      end,
      next_u32 = function()
        return random:next_u32()
      end,
    }
    context.random_seed = entry.random_seed
  end
  return context
end

local function copy_error_detail(detail)
  if type(detail) ~= "table" then
    return nil
  end
  local copied = {}
  for key, value in pairs(detail) do
    if
      type(key) == "string"
      and (type(value) == "string" or type(value) == "boolean" or type(value) == "number")
    then
      copied[key] = value
    end
  end
  return copied
end

local function add_diagnostic(host, entry, hook, error_value)
  host.diagnostics[#host.diagnostics + 1] = {
    detail = copy_error_detail(error_value.detail),
    effect_id = entry.manifest.id,
    frame_sequence = host.frame_sequence,
    hook = hook,
    kind = error_value.kind,
    message = error_value.message,
  }
end

local function callback_error(hook, cause)
  return Errors.new(
    "effect_runtime_error",
    "effect hook failed",
    { cause = tostring(cause), hook = hook }
  )
end

local function call_hook(host, entry, name, argument)
  local callback = entry.hooks[name]
  if callback == nil then
    return true
  end
  if host.callback_count >= host.max_callbacks_per_frame then
    return runtime_error("effect callback frame limit exceeded", { hook = name })
  end
  host.callback_count = host.callback_count + 1
  local context = context_for(host, entry)
  local ok, result = pcall(callback, entry.effect, context, argument)
  if not ok then
    return nil, callback_error(name, result)
  end
  if result ~= nil and result ~= true then
    return runtime_error("effect hook returned an unsupported value", { hook = name })
  end
  return true
end

local shutdown_entry

local function disable_entry(host, entry, hook, error_value)
  if not entry.enabled then
    return
  end
  entry.enabled = false
  add_diagnostic(host, entry, hook, error_value)
  shutdown_entry(host, entry)
end

shutdown_entry = function(host, entry)
  if not entry.initialised or entry.shutdown_attempted then
    return true
  end
  entry.shutdown_attempted = true
  local completed, shutdown_error = call_hook(host, entry, "shutdown")
  if not completed then
    add_diagnostic(host, entry, "shutdown", shutdown_error)
  end
  return true
end

local function invoke(host, entry, name, argument)
  if not entry.enabled then
    return true
  end
  local completed, callback_error_value = call_hook(host, entry, name, argument)
  if not completed then
    disable_entry(host, entry, name, callback_error_value)
  end
  return true
end

local function effect_methods(effect)
  if type(effect) ~= "table" or type(effect.manifest) ~= "function" then
    return nil, Errors.new("effect_load_error", "effect instance must expose manifest")
  end
  local ok, manifest_or_error, detail = pcall(effect.manifest, effect)
  if not ok then
    return nil,
      Errors.new(
        "effect_load_error",
        "effect manifest accessor failed",
        { cause = manifest_or_error }
      )
  end
  if manifest_or_error == nil then
    return nil,
      Errors.new("effect_load_error", "effect manifest accessor failed", { cause = detail })
  end
  local manifest, manifest_error = Manifest.normalise(manifest_or_error)
  if not manifest then
    return nil, manifest_error
  end
  local hooks = {}
  local capabilities = {}
  for _, capability in ipairs(manifest.capabilities) do
    capabilities[capability] = true
  end
  for name, capability in pairs(hook_capabilities) do
    local callback
    if type(effect.hook) == "function" then
      local hook_ok, hook_or_error = pcall(effect.hook, effect, name)
      if not hook_ok then
        return nil,
          Errors.new("effect_load_error", "effect hook accessor failed", {
            cause = hook_or_error,
            hook = name,
          })
      end
      callback = hook_or_error
    else
      callback = effect[name]
    end
    if callback ~= nil and type(callback) ~= "function" then
      return nil, Errors.new("effect_load_error", "effect hook must be a function", { hook = name })
    end
    hooks[name] = callback
    if callback then
      if not capabilities[capability] then
        return nil,
          Errors.new("effect_load_error", "effect hook capability is undeclared", {
            capability = capability,
            hook = name,
          })
      end
    end
  end
  return {
    capabilities = capabilities,
    effect = effect,
    enabled = true,
    hooks = hooks,
    manifest = manifest,
  }
end

local function canvas_runtime(value)
  if type(value) ~= "table" then
    return nil, incompatible("effect canvas capability requires a canvas runtime")
  end
  for _, name in ipairs({ "draw", "restore", "save" }) do
    if type(value[name]) ~= "function" then
      return nil, incompatible("effect canvas runtime is incomplete", { method = name })
    end
  end
  return value
end

local function options(value)
  if value == nil then
    value = {}
  end
  local accepted, accepted_error = exact_fields(value, {
    canvas_runtime = true,
    headless = true,
    max_callbacks_per_frame = true,
    max_delta_us = true,
    max_draw_operations = true,
    max_effects = true,
    max_event_payload_bytes = true,
    random_seed = true,
    session_id = true,
    terminal = true,
    viewport = true,
  }, "effect host options")
  if not accepted then
    return nil, accepted_error
  end
  local headless = value.headless
  if headless == nil then
    headless = true
  end
  if type(headless) ~= "boolean" then
    return config_error("effect host headless must be a boolean")
  end
  local result = {
    headless = headless,
    max_callbacks_per_frame = 4096,
    max_delta_us = 1000000,
    max_draw_operations = 1024,
    max_effects = 16,
    max_event_payload_bytes = 65536,
    random_seed = 0,
    session_id = nil,
    terminal = { columns = 1, rows = 1 },
    viewport = { height = 1, width = 1 },
  }
  for _, name in ipairs({
    "max_callbacks_per_frame",
    "max_delta_us",
    "max_draw_operations",
    "max_effects",
    "max_event_payload_bytes",
  }) do
    if value[name] ~= nil then
      local valid, valid_error = positive_integer(value[name], "effect host " .. name, 0xFFFFFFFF)
      if not valid then
        return nil, valid_error
      end
      result[name] = valid
    end
  end
  if value.session_id ~= nil then
    local session_id, session_error =
      bounded_string(value.session_id, "effect host session id", 128)
    if not session_id then
      return nil, session_error
    end
    result.session_id = session_id
  end
  if value.random_seed ~= nil then
    local random_seed, random_error =
      bounded_integer(value.random_seed, "effect host random seed", 0xFFFFFFFF)
    if not random_seed then
      return nil, random_error
    end
    result.random_seed = random_seed
  end
  if value.viewport ~= nil then
    local viewport, viewport_error =
      dimensions(value.viewport, { height = true, width = true }, "effect host viewport")
    if not viewport then
      return nil, viewport_error
    end
    result.viewport = viewport
  end
  if value.terminal ~= nil then
    local terminal, terminal_error =
      dimensions(value.terminal, { columns = true, rows = true }, "effect host terminal")
    if not terminal then
      return nil, terminal_error
    end
    result.terminal = terminal
  end
  if not headless and value.canvas_runtime ~= nil then
    local runtime, runtime_error_value = canvas_runtime(value.canvas_runtime)
    if not runtime then
      return nil, runtime_error_value
    end
    result.canvas_runtime = runtime
  end
  return result
end

local function draw_operation(kind, arguments)
  local schemas = {
    fill_rect = { height = true, width = true, x = true, y = true },
    line = { x1 = true, x2 = true, y1 = true, y2 = true },
    text = { text = true, x = true, y = true },
  }
  local fields = schemas[kind]
  if not fields then
    return config_error("effect canvas operation is unsupported", { provided = kind })
  end
  local accepted, accepted_error = exact_fields(arguments, fields, "effect canvas operation")
  if not accepted then
    return nil, accepted_error
  end
  local copy = { kind = kind }
  for field in pairs(fields) do
    local value = arguments[field]
    if field == "text" then
      local text, text_error = bounded_string(value, "effect canvas text", 4096)
      if not text then
        return nil, text_error
      end
      copy.text = text
    elseif
      type(value) ~= "number"
      or value ~= value
      or value == math.huge
      or value == -math.huge
    then
      return config_error("effect canvas coordinate is invalid", { field = field })
    else
      copy[field] = value
    end
  end
  return copy
end

local function canvas_facade(host, entry, phase, invocation)
  local facade = { height = host.viewport.height, phase = phase, width = host.viewport.width }
  function facade:draw(kind, arguments)
    if invocation.draw_operations >= host.max_draw_operations then
      return runtime_error("effect canvas draw operation limit exceeded")
    end
    local operation, operation_error = draw_operation(kind, arguments)
    if not operation then
      return nil, operation_error
    end
    local ok, result, detail = pcall(host.canvas_runtime.draw, host.canvas_runtime, operation)
    if not ok or result == false then
      return runtime_error(
        "effect canvas draw failed",
        { cause = tostring(ok and detail or result) }
      )
    end
    invocation.draw_operations = invocation.draw_operations + 1
    return true
  end
  return facade
end

local function invoke_canvas(host, entry, name, phase)
  if not entry.enabled or entry.hooks[name] == nil then
    return true
  end
  local saved, save_result, save_detail = pcall(host.canvas_runtime.save, host.canvas_runtime)
  if not saved or save_result == false then
    disable_entry(
      host,
      entry,
      name,
      runtime_error(
        "effect canvas state save failed",
        { cause = tostring(saved and save_detail or save_result) }
      )
    )
    return true
  end
  local invocation = { draw_operations = 0 }
  local canvas = canvas_facade(host, entry, phase, invocation)
  local completed, callback_error_value = call_hook(host, entry, name, canvas)
  local restored, restore_result, restore_detail =
    pcall(host.canvas_runtime.restore, host.canvas_runtime)
  if not restored or restore_result == false then
    disable_entry(
      host,
      entry,
      name,
      runtime_error(
        "effect canvas state restore failed",
        { cause = tostring(restored and restore_detail or restore_result) }
      )
    )
    return true
  end
  if not completed then
    disable_entry(host, entry, name, callback_error_value)
  end
  return true
end

local function event_payload(host, kind, payload)
  if not event_kinds[kind] then
    return config_error("effect event kind is unsupported", { provided = kind })
  end
  if kind == "bell" then
    local accepted, accepted_error = exact_fields(payload, {}, "effect bell payload")
    if not accepted then
      return nil, accepted_error
    end
    return {}
  end
  if kind == "input" or kind == "output" then
    local accepted, accepted_error =
      exact_fields(payload, { bytes = true }, "effect byte event payload")
    if not accepted then
      return nil, accepted_error
    end
    local bytes, bytes_error =
      bounded_string(payload.bytes, "effect event bytes", host.max_event_payload_bytes)
    if not bytes then
      return nil, bytes_error
    end
    return { bytes = bytes }
  end
  if kind == "cursor" then
    return dimensions(payload, { column = true, row = true }, "effect cursor payload")
  end
  if kind == "resize" then
    return dimensions(
      payload,
      { columns = true, pixel_height = true, pixel_width = true, rows = true },
      "effect resize payload"
    )
  end
  if kind == "screen_switch" then
    local accepted, accepted_error =
      exact_fields(payload, { screen = true }, "effect screen-switch payload")
    if not accepted then
      return nil, accepted_error
    end
    if payload.screen ~= "primary" and payload.screen ~= "alternate" then
      return config_error("effect screen-switch payload is invalid")
    end
    return { screen = payload.screen }
  end
  if kind == "scroll" then
    local accepted, accepted_error = exact_fields(
      payload,
      { bottom = true, count = true, direction = true, top = true },
      "effect scroll payload"
    )
    if not accepted then
      return nil, accepted_error
    end
    local copied, copied_error = dimensions({
      bottom = payload.bottom,
      count = payload.count,
      top = payload.top,
    }, { bottom = true, count = true, top = true }, "effect scroll payload")
    if not copied then
      return nil, copied_error
    end
    if copied.top > copied.bottom or copied.count > copied.bottom - copied.top + 1 then
      return config_error("effect scroll payload is invalid")
    end
    if payload.direction ~= "up" and payload.direction ~= "down" then
      return config_error("effect scroll direction is invalid")
    end
    return {
      bottom = copied.bottom,
      count = copied.count,
      direction = payload.direction,
      top = copied.top,
    }
  end
  if kind == "title" or kind == "replay_reset" then
    local field = kind == "title" and "title" or "reason"
    local accepted, accepted_error =
      exact_fields(payload, { [field] = true }, "effect " .. kind .. " payload")
    if not accepted then
      return nil, accepted_error
    end
    local text, text_error = bounded_string(payload[field], "effect " .. kind .. " text", 1024)
    if not text then
      return nil, text_error
    end
    return { [field] = text }
  end
  if kind == "mode" then
    local accepted, accepted_error =
      exact_fields(payload, { enabled = true, name = true }, "effect mode payload")
    if not accepted then
      return nil, accepted_error
    end
    local name, name_error = bounded_string(payload.name, "effect mode name", 64)
    if not name then
      return nil, name_error
    end
    if type(payload.enabled) ~= "boolean" then
      return config_error("effect mode enabled must be a boolean")
    end
    return { enabled = payload.enabled, name = name }
  end
  if kind == "replay_seek" or kind == "checkpoint_restored" then
    local field = kind == "replay_seek" and "target_us" or "checkpoint_us"
    local accepted, accepted_error =
      exact_fields(payload, { [field] = true }, "effect " .. kind .. " payload")
    if not accepted then
      return nil, accepted_error
    end
    local time, time_error =
      bounded_integer(payload[field], "effect " .. kind .. " time", MAX_TIME_US)
    if not time then
      return nil, time_error
    end
    return { [field] = time }
  end
  local accepted, accepted_error = exact_fields(payload, { ranges = true }, "effect damage payload")
  if not accepted then
    return nil, accepted_error
  end
  local length, length_error = dense_array(payload.ranges, "effect damage ranges")
  if not length then
    return nil, length_error
  end
  if length > host.max_callbacks_per_frame then
    return config_error("effect damage ranges exceed callback limit")
  end
  local ranges = {}
  for index, range in ipairs(payload.ranges) do
    local copied, copied_error = dimensions(
      range,
      { first_column = true, last_column = true, row = true },
      "effect damage range"
    )
    if not copied then
      return nil, copied_error
    end
    if copied.first_column > copied.last_column then
      return config_error("effect damage range is invalid")
    end
    ranges[index] = copied
  end
  return { ranges = ranges }
end

local function cell_snapshot(value, full_redraw)
  local accepted, accepted_error = exact_fields(value, {
    attributes = true,
    background = true,
    column = true,
    cursor = true,
    damage = true,
    frame_sequence = true,
    foreground = true,
    row = true,
    screen = true,
    text = true,
    width = true,
  }, "effect cell")
  if not accepted then
    return nil, accepted_error
  end
  local column, column_error = positive_integer(value.column, "effect cell column", 0xFFFFFFFF)
  if not column then
    return nil, column_error
  end
  local row, row_error = positive_integer(value.row, "effect cell row", 0xFFFFFFFF)
  if not row then
    return nil, row_error
  end
  local text, text_error = bounded_string(value.text, "effect cell text", 4096)
  if not text then
    return nil, text_error
  end
  if value.width ~= 1 and value.width ~= 2 then
    return config_error("effect cell width is invalid")
  end
  local attributes, attributes_error =
    bounded_integer(value.attributes, "effect cell attributes", 0xFFFFFFFF)
  if not attributes then
    return nil, attributes_error
  end
  if type(value.cursor) ~= "boolean" or type(value.damage) ~= "boolean" then
    return config_error("effect cell flags must be booleans")
  end
  if value.screen ~= "primary" and value.screen ~= "alternate" then
    return config_error("effect cell screen is invalid")
  end
  local foreground, foreground_error = colour(value.foreground, "effect cell foreground")
  if not foreground then
    return nil, foreground_error
  end
  local background, background_error = colour(value.background, "effect cell background")
  if not background then
    return nil, background_error
  end
  return {
    attributes = attributes,
    background = background,
    column = column,
    cursor = value.cursor,
    damage = full_redraw or value.damage,
    foreground = foreground,
    row = row,
    screen = value.screen,
    text = text,
    width = value.width,
  }
end

function Host.new(effects, configuration)
  local settings, settings_error = options(configuration)
  if not settings then
    return nil, settings_error
  end
  local count, effects_error = dense_array(effects, "effect host effects")
  if not count then
    return nil, effects_error
  end
  if count > settings.max_effects then
    return config_error("effect host effect limit exceeded")
  end
  local entries = {}
  for index, effect in ipairs(effects) do
    local entry, entry_error = effect_methods(effect)
    if not entry then
      return nil, entry_error
    end
    for _, capability in ipairs(entry.manifest.capabilities) do
      if canvas_capabilities[capability] then
        if settings.headless then
          return incompatible(
            "headless effect host rejects canvas capability",
            { capability = capability }
          )
        end
        if not settings.canvas_runtime then
          return incompatible(
            "effect canvas capability is unavailable",
            { capability = capability }
          )
        end
      end
    end
    if entry.capabilities.deterministic_random then
      local seed, seed_error = Random.derive(settings.random_seed, entry.manifest.id)
      if not seed then
        return nil, seed_error
      end
      local random, random_error = Random.new(seed)
      if not random then
        return nil, random_error
      end
      entry.random = random
      entry.random_seed = seed
    end
    entries[index] = entry
  end
  local host = setmetatable({
    callback_count = 0,
    canvas_runtime = settings.canvas_runtime,
    diagnostics = {},
    effects = entries,
    elapsed_us = 0,
    event_sequence = 0,
    frame_sequence = 0,
    headless = settings.headless,
    last_event_timestamp_us = 0,
    max_callbacks_per_frame = settings.max_callbacks_per_frame,
    max_delta_us = settings.max_delta_us,
    max_draw_operations = settings.max_draw_operations,
    max_event_payload_bytes = settings.max_event_payload_bytes,
    session_id = settings.session_id,
    terminal = settings.terminal,
    viewport = settings.viewport,
  }, host_mt)
  for _, entry in ipairs(host.effects) do
    if entry.hooks.init then
      local initialized, init_error = call_hook(host, entry, "init")
      if initialized then
        entry.initialised = true
      else
        entry.enabled = false
        add_diagnostic(host, entry, "init", init_error)
      end
    else
      entry.initialised = true
    end
  end
  return host
end

function host_mt:update(delta_us)
  local delta, delta_error = bounded_integer(delta_us, "effect update delta_us", self.max_delta_us)
  if not delta then
    return nil, delta_error
  end
  if self.elapsed_us > MAX_TIME_US - delta then
    return runtime_error("effect elapsed time is exhausted")
  end
  self.callback_count = 0
  self.frame_sequence = self.frame_sequence + 1
  self.elapsed_us = self.elapsed_us + delta
  for _, entry in ipairs(self.effects) do
    invoke(self, entry, "update", delta)
  end
  return true
end

function host_mt:advance(delta_us)
  local delta, delta_error = bounded_integer(delta_us, "effect advance delta_us", MAX_TIME_US)
  if not delta then
    return nil, delta_error
  end
  if delta == 0 then
    return self:update(0)
  end
  while delta > 0 do
    local step = math.min(delta, self.max_delta_us)
    local advanced, advance_error = self:update(step)
    if not advanced then
      return nil, advance_error
    end
    delta = delta - step
  end
  return true
end

function host_mt:emit(kind, payload, timestamp_us)
  local timestamp, timestamp_error =
    bounded_integer(timestamp_us, "effect event timestamp_us", MAX_TIME_US)
  if not timestamp then
    return nil, timestamp_error
  end
  if timestamp < self.last_event_timestamp_us or timestamp > self.elapsed_us then
    return config_error("effect event timestamp is outside elapsed order")
  end
  local copied_payload, payload_error = event_payload(self, kind, payload)
  if not copied_payload then
    return nil, payload_error
  end
  if self.event_sequence >= MAX_TIME_US then
    return runtime_error("effect event sequence is exhausted")
  end
  self.event_sequence = self.event_sequence + 1
  self.last_event_timestamp_us = timestamp
  local event = {
    kind = kind,
    payload = copied_payload,
    sequence = self.event_sequence,
    timestamp_us = timestamp,
    version = 1,
  }
  for _, entry in ipairs(self.effects) do
    local delivered_payload, delivered_payload_error =
      event_payload(self, event.kind, event.payload)
    if not delivered_payload then
      return nil, delivered_payload_error
    end
    invoke(self, entry, "on_event", {
      kind = event.kind,
      payload = delivered_payload,
      sequence = event.sequence,
      timestamp_us = event.timestamp_us,
      version = event.version,
    })
  end
  return {
    kind = event.kind,
    payload = event.payload,
    sequence = event.sequence,
    timestamp_us = event.timestamp_us,
    version = event.version,
  }
end

function host_mt:observe_cells(cells, full_redraw)
  if type(full_redraw) ~= "boolean" then
    return config_error("effect full_redraw must be a boolean")
  end
  local count, cells_error = dense_array(cells, "effect cells")
  if not count then
    return nil, cells_error
  end
  local previous_row = 0
  local previous_column = 0
  for _, source in ipairs(cells) do
    local cell, cell_error = cell_snapshot(source, full_redraw)
    if not cell then
      return nil, cell_error
    end
    if cell.row < previous_row or (cell.row == previous_row and cell.column <= previous_column) then
      return config_error("effect cells must be in strict row-major order")
    end
    previous_row = cell.row
    previous_column = cell.column
    cell.frame_sequence = self.frame_sequence
    for _, entry in ipairs(self.effects) do
      local delivered, delivered_error = cell_snapshot(cell, false)
      if not delivered then
        return nil, delivered_error
      end
      delivered.frame_sequence = cell.frame_sequence
      invoke(self, entry, "on_cell", delivered)
    end
  end
  return true
end

function host_mt:before_canvas()
  for _, entry in ipairs(self.effects) do
    invoke_canvas(self, entry, "before_canvas", "before")
  end
  return true
end

function host_mt:after_canvas()
  for _, entry in ipairs(self.effects) do
    invoke_canvas(self, entry, "after_canvas", "after")
  end
  return true
end

function host_mt:resize(viewport, terminal, timestamp_us)
  local next_viewport
  if viewport == nil then
    next_viewport = { height = self.viewport.height, width = self.viewport.width }
  else
    local viewport_error
    next_viewport, viewport_error =
      dimensions(viewport, { height = true, width = true }, "effect host viewport")
    if not next_viewport then
      return nil, viewport_error
    end
  end
  local next_terminal, terminal_error =
    dimensions(terminal, { columns = true, rows = true }, "effect host terminal")
  if not next_terminal then
    return nil, terminal_error
  end
  self.viewport = next_viewport
  self.terminal = next_terminal
  return self:emit("resize", {
    columns = next_terminal.columns,
    pixel_height = next_viewport.height,
    pixel_width = next_viewport.width,
    rows = next_terminal.rows,
  }, timestamp_us)
end

function host_mt:shutdown()
  for _, entry in ipairs(self.effects) do
    shutdown_entry(self, entry)
  end
  return true
end

function host_mt:limits()
  return {
    max_callbacks_per_frame = self.max_callbacks_per_frame,
    max_delta_us = self.max_delta_us,
    max_event_payload_bytes = self.max_event_payload_bytes,
  }
end

function host_mt:status()
  local diagnostics = {}
  for index, diagnostic in ipairs(self.diagnostics) do
    diagnostics[index] = {
      detail = copy_error_detail(diagnostic.detail),
      effect_id = diagnostic.effect_id,
      frame_sequence = diagnostic.frame_sequence,
      hook = diagnostic.hook,
      kind = diagnostic.kind,
      message = diagnostic.message,
    }
  end
  local effects = {}
  for index, entry in ipairs(self.effects) do
    effects[index] = {
      enabled = entry.enabled,
      id = entry.manifest.id,
      initialised = entry.initialised,
      shutdown_attempted = entry.shutdown_attempted == true,
    }
  end
  return {
    callback_count = self.callback_count,
    diagnostics = diagnostics,
    effects = effects,
    elapsed_us = self.elapsed_us,
    event_sequence = self.event_sequence,
    frame_sequence = self.frame_sequence,
  }
end

return Host
