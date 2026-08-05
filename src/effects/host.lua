local Errors = require("runtime.errors")
local Manifest = require("effects.manifest")
local Random = require("effects.random")

local Host = {}
local host_mt = {}
host_mt.__index = host_mt

Host.contract = {
  advance = "advance(delta_us) -> true | nil, error",
  before_canvas = "before_canvas() -> true | nil, error",
  begin_visual_frame = "begin_visual_frame(frame) -> visual_frame | nil, error",
  after_canvas = "after_canvas() -> true | nil, error",
  begin_canvas_frame = "begin_canvas_frame(frame) -> canvas_frame | nil, error",
  canvas_capable = "canvas_capable() -> boolean",
  cell_transform_capable = "cell_transform_capable() -> boolean",
  constructor = "new(effects, options?) -> effect_host | nil, error",
  disable = "disable(effect_id) -> true | nil, error",
  end_canvas_frame = "end_canvas_frame() -> true",
  end_visual_frame = "end_visual_frame() -> true",
  enable = "enable(effect_id) -> true | nil, error",
  emit = "emit(kind, payload, timestamp_us) -> event | nil, error",
  limits = "limits() -> lifecycle_limits",
  observe_cells = "observe_cells(cells, full_redraw) -> true | nil, error",
  reorder = "reorder(effect_ids) -> true | nil, error",
  replace = "replace(effect_id, candidate, options?) -> true | nil, error",
  resize = "resize(viewport|nil, terminal, timestamp_us) -> event | nil, error",
  set_canvas_runtime = "set_canvas_runtime(runtime) -> true | nil, error",
  shutdown = "shutdown() -> true",
  status = "status() -> effect_host_status",
  transform_cell = "transform_cell(cell, full_redraw) -> cell_transform | nil, error",
  update = "update(delta_us) -> true | nil, error",
  visual_needs_redraw = "visual_needs_redraw() -> boolean | nil, error",
}

local MAX_TIME_US = 9007199254740991

local hook_capabilities = {
  after_canvas = "canvas_after",
  before_canvas = "canvas_before",
  init = "lifecycle",
  needs_redraw = "visual_state",
  on_cell = "cell_observation",
  on_event = "terminal_events",
  shutdown = "lifecycle",
  transform_cell = "cell_transform",
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

local function incompatible_failure(message, detail)
  local _, error_value = incompatible(message, detail)
  return error_value
end

local function runtime_error(message, detail)
  return nil, Errors.new("effect_runtime_error", message, detail)
end

local function runtime_failure(message, detail)
  local _, error_value = runtime_error(message, detail)
  return error_value
end

local function reload_error(message, detail)
  return nil, Errors.new("effect_reload_error", message, detail)
end

local function reload_failure(message, detail)
  local _, error_value = reload_error(message, detail)
  return error_value
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

local function canvas_colour(value)
  if value == nil then
    return nil
  end
  local accepted, accepted_error = exact_fields(
    value,
    { alpha = true, blue = true, green = true, red = true },
    "effect canvas colour"
  )
  if not accepted then
    return nil, accepted_error
  end
  local copy = {}
  for _, field in ipairs({ "red", "green", "blue", "alpha" }) do
    local component = value[field]
    if
      type(component) ~= "number"
      or component ~= component
      or component == math.huge
      or component == -math.huge
      or component < 0
      or component > 1
    then
      return config_error("effect canvas colour component is invalid", { field = field })
    end
    copy[field] = component
  end
  return copy
end

local function context_for(host, entry, hook)
  local canvas_frame = canvas_capabilities[hook_capabilities[hook]] and host.canvas_frame or nil
  local visual_frame = canvas_frame and nil or host.visual_frame
  local frame = canvas_frame or visual_frame
  local terminal = frame and frame.terminal or host.terminal
  local viewport = frame and frame.viewport or host.viewport
  local capabilities = {}
  for _, capability in ipairs(entry.manifest.capabilities) do
    capabilities[capability] = true
  end
  local context = {
    api_version = Manifest.api_version,
    capabilities = capabilities,
    effect_id = entry.manifest.id,
    elapsed_us = host.elapsed_us,
    frame_sequence = frame and frame.sequence or host.frame_sequence,
    runtime = {
      canvas = host.canvas_runtime ~= nil or host.canvas_capability,
      headless = host.headless,
    },
    session_id = host.session_id,
    terminal = { columns = terminal.columns, rows = terminal.rows },
    viewport = { height = viewport.height, width = viewport.width },
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
  local context = context_for(host, entry, name)
  host.callback_depth = host.callback_depth + 1
  local ok, result = pcall(callback, entry.effect, context, argument)
  host.callback_depth = host.callback_depth - 1
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
  entry.disabled_reason = "failure"
  add_diagnostic(host, entry, hook, error_value)
  shutdown_entry(host, entry)
end

local function entry_for(host, effect_id)
  if type(effect_id) ~= "string" or effect_id == "" then
    return config_error("effect id must be a non-empty string")
  end
  for _, entry in ipairs(host.effects) do
    if entry.manifest.id == effect_id then
      return entry
    end
  end
  return config_error("effect id is not loaded", { effect_id = effect_id })
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
  if capabilities.visual_state and not capabilities.cell_transform then
    return nil,
      Errors.new("effect_load_error", "visual-state capability requires cell-transform capability")
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
    return incompatible("effect canvas capability requires a canvas runtime")
  end
  for _, name in ipairs({ "draw", "restore", "save" }) do
    if type(value[name]) ~= "function" then
      return incompatible("effect canvas runtime is incomplete", { method = name })
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
    effect_metadata = true,
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
    effect_metadata = {},
    headless = headless,
    max_callbacks_per_frame = 65536,
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
  if value.effect_metadata ~= nil then
    if type(value.effect_metadata) ~= "table" then
      return config_error("effect host metadata must be a table")
    end
    result.effect_metadata = value.effect_metadata
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

local function copy_metadata(value)
  local copy = {}
  if value.label ~= nil then
    copy.label = value.label
  end
  if value.source_identity ~= nil then
    copy.source_identity = value.source_identity
  end
  return copy
end

local function metadata_by_effect(value, ids)
  local result = {}
  for effect_id, metadata in pairs(value) do
    if type(effect_id) ~= "string" or ids[effect_id] == nil then
      return config_error(
        "effect host metadata contains an unknown effect",
        { effect_id = effect_id }
      )
    end
    local accepted, accepted_error =
      exact_fields(metadata, { label = true, source_identity = true }, "effect host metadata")
    if not accepted then
      return nil, accepted_error
    end
    local copy = {}
    for _, field in ipairs({ "label", "source_identity" }) do
      if metadata[field] ~= nil then
        local bounded, bounded_error = bounded_string(
          metadata[field],
          "effect host metadata " .. field,
          field == "label" and 128 or 256
        )
        if not bounded or bounded == "" then
          return nil,
            bounded_error or Errors.new("config_error", "effect host metadata must be non-empty")
        end
        copy[field] = bounded
      end
    end
    result[effect_id] = copy
  end
  return result
end

local function reload_options(value)
  if value == nil then
    return {}
  end
  local accepted, accepted_error =
    exact_fields(value, { source_identity = true }, "effect reload options")
  if not accepted then
    return nil, accepted_error
  end
  if value.source_identity == nil then
    return {}
  end
  local source_identity, source_error =
    bounded_string(value.source_identity, "effect reload source identity", 256)
  if not source_identity or source_identity == "" then
    return config_error("effect reload source identity must be non-empty")
  end
  return { source_identity = source_identity }
end

local function sorted_keys(value)
  local keys = {}
  for key in pairs(value) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function error_cause(error_value)
  if Errors.is(error_value) then
    return {
      cause = error_value.message,
      cause_kind = error_value.kind,
    }
  end
  return { cause = tostring(error_value), cause_kind = "unknown" }
end

local function reload_from(stage, error_value)
  local detail = error_cause(error_value)
  detail.stage = stage
  return reload_failure("effect replacement failed", detail)
end

local function entry_parameters(entry)
  if type(entry.effect.parameters) ~= "function" then
    return nil, Errors.new("effect_load_error", "effect instance must expose parameters")
  end
  local ok, values_or_error, detail = pcall(entry.effect.parameters, entry.effect)
  if not ok or values_or_error == nil then
    return nil,
      Errors.new("effect_load_error", "effect parameter accessor failed", {
        cause = ok and tostring(detail) or tostring(values_or_error),
      })
  end
  return Manifest.parameters(entry.manifest, values_or_error)
end

local function configure_parameters(entry, values)
  if type(entry.effect.set_parameters) ~= "function" then
    return nil, Errors.new("effect_load_error", "effect instance must expose set_parameters")
  end
  local ok, configured, configure_error = pcall(entry.effect.set_parameters, entry.effect, values)
  if not ok or configured ~= true then
    return nil,
      Errors.new("effect_load_error", "effect parameter configuration failed", {
        cause = ok and tostring(configure_error) or tostring(configured),
      })
  end
  return true
end

local function initialise_random(host, entry)
  if not entry.capabilities.deterministic_random then
    return true
  end
  local seed, seed_error = Random.derive(host.random_seed, entry.manifest.id)
  if not seed then
    return nil, seed_error
  end
  local random, random_error = Random.new(seed)
  if not random then
    return nil, random_error
  end
  entry.random = random
  entry.random_seed = seed
  return true
end

local function capability_compatible(host, entry)
  for _, capability in ipairs(entry.manifest.capabilities) do
    if canvas_capabilities[capability] and (host.headless or not host.canvas_capability) then
      return nil,
        incompatible_failure("effect replacement requires an unnegotiated canvas capability", {
          capability = capability,
        })
    end
    if capability == "cell_transform" and not host.cell_transform_capability then
      return nil,
        incompatible_failure(
          "effect replacement requires an unnegotiated cell-transform capability"
        )
    end
  end
  return true
end

local function migration_values(old_entry, candidate_entry)
  local old_values, old_values_error = entry_parameters(old_entry)
  if not old_values then
    return nil, old_values_error
  end
  local values = {}
  local migrations = {}
  for _, name in ipairs(sorted_keys(old_entry.manifest.parameters)) do
    local old_schema = old_entry.manifest.parameters[name]
    local new_schema = candidate_entry.manifest.parameters[name]
    if new_schema == nil then
      migrations[#migrations + 1] = { name = name, reason = "removed" }
    elseif old_schema.type ~= new_schema.type then
      migrations[#migrations + 1] = { name = name, reason = "type_changed" }
    else
      local normalised, validation_error = Manifest.parameters(candidate_entry.manifest, {
        [name] = old_values[name],
      })
      if normalised then
        values[name] = normalised[name]
      else
        migrations[#migrations + 1] = {
          name = name,
          reason = "invalid",
          validation_kind = validation_error.kind,
        }
      end
    end
  end
  for _, name in ipairs(sorted_keys(candidate_entry.manifest.parameters)) do
    if old_entry.manifest.parameters[name] == nil then
      migrations[#migrations + 1] = { name = name, reason = "new_default" }
    end
  end
  local migrated, migrated_error = Manifest.parameters(candidate_entry.manifest, values)
  if not migrated then
    return nil, migrated_error
  end
  return migrated, migrations
end

local function add_reload_migration(host, entry, migration)
  host.diagnostics[#host.diagnostics + 1] = {
    detail = {
      parameter = migration.name,
      reason = migration.reason,
      validation_kind = migration.validation_kind,
    },
    effect_id = entry.manifest.id,
    frame_sequence = host.frame_sequence,
    hook = "replace",
    kind = "effect_reload_migration",
    message = "effect parameter used replacement default",
  }
end

local function canvas_viewport(host)
  return host.canvas_frame and host.canvas_frame.viewport or host.viewport
end

local function draw_operation(host, kind, arguments)
  local schemas = {
    fill_rect = { colour = true, height = true, width = true, x = true, y = true },
    line = { colour = true, x1 = true, x2 = true, y1 = true, y2 = true },
    text = { colour = true, text = true, x = true, y = true },
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
    if field == "colour" then
      local selected, selected_error = canvas_colour(value)
      if selected_error then
        return nil, selected_error
      end
      copy.colour = selected
    elseif field == "text" then
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
  local viewport = canvas_viewport(host)
  if kind == "fill_rect" then
    if copy.width < 0 or copy.height < 0 then
      return config_error("effect canvas rectangle size is invalid")
    end
    if
      copy.x < 0
      or copy.y < 0
      or copy.x + copy.width > viewport.width
      or copy.y + copy.height > viewport.height
    then
      return config_error("effect canvas rectangle is outside the viewport")
    end
  elseif kind == "line" then
    for _, field in ipairs({ "x1", "x2" }) do
      if copy[field] < 0 or copy[field] > viewport.width then
        return config_error("effect canvas line is outside the viewport")
      end
    end
    for _, field in ipairs({ "y1", "y2" }) do
      if copy[field] < 0 or copy[field] > viewport.height then
        return config_error("effect canvas line is outside the viewport")
      end
    end
  elseif copy.x < 0 or copy.x > viewport.width or copy.y < 0 or copy.y > viewport.height then
    return config_error("effect canvas text origin is outside the viewport")
  end
  return copy
end

local function canvas_facade(host, entry, phase, invocation)
  local viewport = host.canvas_frame and host.canvas_frame.viewport or host.viewport
  local facade = { height = viewport.height, phase = phase, width = viewport.width }
  function facade:draw(kind, arguments)
    if not invocation.active then
      return runtime_error("effect canvas facade is expired")
    end
    if invocation.draw_operations >= host.max_draw_operations then
      invocation.error = runtime_failure("effect canvas draw operation limit exceeded")
      return nil, invocation.error
    end
    local operation, operation_error = draw_operation(host, kind, arguments)
    if not operation then
      invocation.error = runtime_failure("effect canvas operation is invalid", {
        cause = operation_error.message,
        cause_kind = operation_error.kind,
      })
      return nil, invocation.error
    end
    local ok, result, detail = pcall(host.canvas_runtime.draw, host.canvas_runtime, operation)
    if not ok or not result then
      invocation.error =
        runtime_failure("effect canvas draw failed", { cause = tostring(ok and detail or result) })
      return nil, invocation.error
    end
    invocation.draw_operations = invocation.draw_operations + 1
    return true
  end
  function facade:fill_rect(x, y, width, height, colour)
    return self:draw("fill_rect", {
      colour = colour,
      height = height,
      width = width,
      x = x,
      y = y,
    })
  end
  function facade:line(x1, y1, x2, y2, colour)
    return self:draw("line", { colour = colour, x1 = x1, x2 = x2, y1 = y1, y2 = y2 })
  end
  function facade:text(text, x, y, colour)
    return self:draw("text", { colour = colour, text = text, x = x, y = y })
  end
  return facade
end

local function invoke_canvas(host, entry, name, phase)
  if
    not entry.enabled
    or not entry.capabilities[hook_capabilities[name]]
    or entry.hooks[name] == nil
  then
    return true
  end
  if host.canvas_runtime == nil then
    disable_entry(host, entry, name, incompatible_failure("effect canvas runtime is unavailable"))
    return true
  end
  local saved, save_result, save_detail = pcall(host.canvas_runtime.save, host.canvas_runtime)
  if not saved or not save_result then
    disable_entry(
      host,
      entry,
      name,
      runtime_failure(
        "effect canvas state save failed",
        { cause = tostring(saved and save_detail or save_result) }
      )
    )
    return true
  end
  local invocation = { active = true, draw_operations = 0 }
  local canvas = canvas_facade(host, entry, phase, invocation)
  local completed, callback_error_value = call_hook(host, entry, name, canvas)
  invocation.active = false
  if completed and invocation.error then
    completed = nil
    callback_error_value = invocation.error
  end
  local restored, restore_result, restore_detail =
    pcall(host.canvas_runtime.restore, host.canvas_runtime)
  if not restored or not restore_result then
    disable_entry(
      host,
      entry,
      name,
      runtime_failure(
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

local function cell_transform(value)
  if value == nil then
    return nil
  end
  local accepted, accepted_error =
    exact_fields(value, { offset_x = true, offset_y = true }, "effect cell transform")
  if not accepted then
    return nil, accepted_error
  end
  local result = {}
  for _, field in ipairs({ "offset_x", "offset_y" }) do
    local offset = value[field]
    if
      type(offset) ~= "number"
      or offset ~= offset
      or offset == math.huge
      or offset == -math.huge
      or offset < -1
      or offset > 1
    then
      return config_error("effect cell transform offset is invalid", { field = field })
    end
    result[field] = offset
  end
  return result
end

local function call_transform(host, entry, cell)
  local callback = entry.hooks.transform_cell
  if callback == nil then
    return true
  end
  if host.callback_count >= host.max_callbacks_per_frame then
    return runtime_error("effect callback frame limit exceeded", { hook = "transform_cell" })
  end
  host.callback_count = host.callback_count + 1
  local context = context_for(host, entry, "transform_cell")
  host.callback_depth = host.callback_depth + 1
  local completed, result = pcall(callback, entry.effect, context, cell)
  host.callback_depth = host.callback_depth - 1
  if not completed then
    return nil, callback_error("transform_cell", result)
  end
  local transform, transform_error = cell_transform(result)
  if not transform and transform_error then
    return runtime_error("effect cell transform is invalid", {
      cause = transform_error.message,
      cause_kind = transform_error.kind,
    })
  end
  return true, transform
end

local function call_needs_redraw(host, entry)
  local callback = entry.hooks.needs_redraw
  if callback == nil then
    return false
  end
  if host.callback_count >= host.max_callbacks_per_frame then
    return runtime_error("effect callback frame limit exceeded", { hook = "needs_redraw" })
  end
  host.callback_count = host.callback_count + 1
  local context = context_for(host, entry, "needs_redraw")
  host.callback_depth = host.callback_depth + 1
  local completed, result = pcall(callback, entry.effect, context)
  host.callback_depth = host.callback_depth - 1
  if not completed then
    return nil, callback_error("needs_redraw", result)
  end
  if type(result) ~= "boolean" then
    return runtime_error("effect needs_redraw hook returned an invalid value")
  end
  return result
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
  local has_canvas_capability = false
  local has_cell_transform_capability = false
  local seen_ids = {}
  for index, effect in ipairs(effects) do
    local entry, entry_error = effect_methods(effect)
    if not entry then
      return nil, entry_error
    end
    if seen_ids[entry.manifest.id] then
      return config_error("effect host ids must be unique", { effect_id = entry.manifest.id })
    end
    seen_ids[entry.manifest.id] = true
    for _, capability in ipairs(entry.manifest.capabilities) do
      if canvas_capabilities[capability] then
        has_canvas_capability = true
        if settings.headless then
          return incompatible(
            "headless effect host rejects canvas capability",
            { capability = capability }
          )
        end
      end
      if capability == "cell_transform" then
        has_cell_transform_capability = true
      end
    end
    entries[index] = entry
  end
  local configured_metadata, metadata_error = metadata_by_effect(settings.effect_metadata, seen_ids)
  if not configured_metadata then
    return nil, metadata_error
  end
  for _, entry in ipairs(entries) do
    entry.metadata = configured_metadata[entry.manifest.id] or {}
    entry.reload_generation = 0
    local initialised_random, random_error = initialise_random({
      random_seed = settings.random_seed,
    }, entry)
    if not initialised_random then
      return nil, random_error
    end
  end
  local host = setmetatable({
    canvas_capability = has_canvas_capability,
    canvas_frame = nil,
    canvas_frame_sequence = 0,
    callback_count = 0,
    callback_depth = 0,
    cell_transform_capability = has_cell_transform_capability,
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
    random_seed = settings.random_seed,
    session_id = settings.session_id,
    terminal = settings.terminal,
    visual_frame = nil,
    visual_frame_sequence = 0,
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

function host_mt:canvas_capable()
  return self.canvas_capability
end

function host_mt:cell_transform_capable()
  return self.cell_transform_capability
end

function host_mt:set_canvas_runtime(runtime)
  if self.headless then
    return incompatible("headless effect host cannot bind a canvas runtime")
  end
  if self.canvas_frame ~= nil then
    return runtime_error("cannot replace canvas runtime during a canvas frame")
  end
  local valid_runtime, runtime_error_value = canvas_runtime(runtime)
  if not valid_runtime then
    return nil, runtime_error_value
  end
  self.canvas_runtime = valid_runtime
  return true
end

function host_mt:begin_canvas_frame(frame)
  local accepted, accepted_error =
    exact_fields(frame, { terminal = true, viewport = true }, "effect canvas frame")
  if not accepted then
    return nil, accepted_error
  end
  if self.canvas_frame ~= nil then
    return runtime_error("effect canvas frame is already active")
  end
  local terminal, terminal_error =
    dimensions(frame.terminal, { columns = true, rows = true }, "effect canvas frame terminal")
  if not terminal then
    return nil, terminal_error
  end
  local viewport, viewport_error =
    dimensions(frame.viewport, { height = true, width = true }, "effect canvas frame viewport")
  if not viewport then
    return nil, viewport_error
  end
  if self.canvas_frame_sequence >= MAX_TIME_US then
    return runtime_error("effect canvas frame sequence is exhausted")
  end
  self.canvas_frame_sequence = self.canvas_frame_sequence + 1
  self.callback_count = 0
  local entries = {}
  for _, entry in ipairs(self.effects) do
    if
      entry.enabled
      and (
        (entry.capabilities.canvas_before and entry.hooks.before_canvas ~= nil)
        or (entry.capabilities.canvas_after and entry.hooks.after_canvas ~= nil)
      )
    then
      entries[#entries + 1] = entry
    end
  end
  self.canvas_frame = {
    entries = entries,
    sequence = self.canvas_frame_sequence,
    terminal = terminal,
    viewport = viewport,
  }
  return {
    active = #entries > 0,
    sequence = self.canvas_frame.sequence,
    terminal = { columns = terminal.columns, rows = terminal.rows },
    viewport = { height = viewport.height, width = viewport.width },
  }
end

function host_mt:end_canvas_frame()
  self.canvas_frame = nil
  return true
end

function host_mt:begin_visual_frame(frame)
  local accepted, accepted_error =
    exact_fields(frame, { terminal = true, viewport = true }, "effect visual frame")
  if not accepted then
    return nil, accepted_error
  end
  if self.visual_frame ~= nil then
    return runtime_error("effect visual frame is already active")
  end
  local terminal, terminal_error =
    dimensions(frame.terminal, { columns = true, rows = true }, "effect visual frame terminal")
  if not terminal then
    return nil, terminal_error
  end
  local viewport, viewport_error =
    dimensions(frame.viewport, { height = true, width = true }, "effect visual frame viewport")
  if not viewport then
    return nil, viewport_error
  end
  if self.visual_frame_sequence >= MAX_TIME_US then
    return runtime_error("effect visual frame sequence is exhausted")
  end
  self.visual_frame_sequence = self.visual_frame_sequence + 1
  self.callback_count = 0
  local entries = {}
  for _, entry in ipairs(self.effects) do
    if
      entry.enabled
      and (
        (entry.capabilities.cell_transform and entry.hooks.transform_cell ~= nil)
        or (entry.capabilities.visual_state and entry.hooks.needs_redraw ~= nil)
      )
    then
      entries[#entries + 1] = entry
    end
  end
  self.visual_frame = {
    entries = entries,
    redraw = false,
    sequence = self.visual_frame_sequence,
    terminal = terminal,
    viewport = viewport,
  }
  for _, entry in ipairs(entries) do
    if entry.enabled and entry.capabilities.visual_state and entry.hooks.needs_redraw then
      local redraw, redraw_error = call_needs_redraw(self, entry)
      if redraw == nil then
        disable_entry(self, entry, "needs_redraw", redraw_error)
      elseif redraw then
        self.visual_frame.redraw = true
      end
    end
  end
  return {
    active = #entries > 0,
    redraw = self.visual_frame.redraw,
    sequence = self.visual_frame.sequence,
    terminal = { columns = terminal.columns, rows = terminal.rows },
    viewport = { height = viewport.height, width = viewport.width },
  }
end

function host_mt:end_visual_frame()
  self.visual_frame = nil
  return true
end

function host_mt:visual_needs_redraw()
  if self.visual_frame == nil then
    return runtime_error("effect visual frame is not active")
  end
  return self.visual_frame.redraw
end

function host_mt:transform_cell(source, full_redraw)
  if self.visual_frame == nil then
    return runtime_error("effect visual frame is not active")
  end
  if type(full_redraw) ~= "boolean" then
    return config_error("effect full_redraw must be a boolean")
  end
  local first_cell, cell_error = cell_snapshot(source, full_redraw)
  if not first_cell then
    return nil, cell_error
  end
  local result = { offset_x = 0, offset_y = 0 }
  for _, entry in ipairs(self.visual_frame.entries) do
    if entry.enabled and entry.capabilities.cell_transform and entry.hooks.transform_cell then
      local delivered = first_cell
      if delivered then
        first_cell = nil
      else
        local delivered_error
        delivered, delivered_error = cell_snapshot(source, full_redraw)
        if not delivered then
          return nil, delivered_error
        end
      end
      delivered.frame_sequence = self.visual_frame.sequence
      local transformed, transform_or_error = call_transform(self, entry, delivered)
      if not transformed then
        disable_entry(self, entry, "transform_cell", transform_or_error)
      elseif transform_or_error then
        result.offset_x = math.max(-1, math.min(1, result.offset_x + transform_or_error.offset_x))
        result.offset_y = math.max(-1, math.min(1, result.offset_y + transform_or_error.offset_y))
      end
    end
  end
  return result
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

function host_mt:disable(effect_id)
  local entry, entry_error = entry_for(self, effect_id)
  if not entry then
    return nil, entry_error
  end
  if entry.disabled_reason == "failure" then
    return runtime_error(
      "failed effect cannot be manually disabled or re-enabled",
      { effect_id = effect_id }
    )
  end
  entry.enabled = false
  entry.disabled_reason = "manual"
  return true
end

function host_mt:enable(effect_id)
  local entry, entry_error = entry_for(self, effect_id)
  if not entry then
    return nil, entry_error
  end
  if entry.disabled_reason == "failure" then
    return runtime_error("failed effect cannot be re-enabled", { effect_id = effect_id })
  end
  entry.enabled = true
  entry.disabled_reason = nil
  return true
end

function host_mt:reorder(effect_ids)
  local length, ids_error = dense_array(effect_ids, "effect host reorder ids")
  if not length then
    return nil, ids_error
  end
  if length ~= #self.effects then
    return config_error("effect host reorder must include every loaded effect")
  end
  local by_id = {}
  for _, entry in ipairs(self.effects) do
    by_id[entry.manifest.id] = entry
  end
  local reordered = {}
  local seen = {}
  for index, effect_id in ipairs(effect_ids) do
    if type(effect_id) ~= "string" or by_id[effect_id] == nil then
      return config_error(
        "effect host reorder contains an unknown effect",
        { effect_id = effect_id }
      )
    end
    if seen[effect_id] then
      return config_error(
        "effect host reorder contains a duplicate effect",
        { effect_id = effect_id }
      )
    end
    seen[effect_id] = true
    reordered[index] = by_id[effect_id]
  end
  self.effects = reordered
  return true
end

function host_mt:replace(effect_id, candidate, replacement)
  if self.callback_depth ~= 0 then
    return reload_error(
      "effect replacement requires a quiescent frame boundary",
      { stage = "callback" }
    )
  end
  if self.canvas_frame ~= nil or self.visual_frame ~= nil then
    return reload_error(
      "effect replacement requires a quiescent frame boundary",
      { stage = "frame" }
    )
  end
  local request, request_error = reload_options(replacement)
  if not request then
    return nil, reload_from("request", request_error)
  end
  local old_entry, old_error = entry_for(self, effect_id)
  if not old_entry then
    return nil, reload_from("target", old_error)
  end
  local index
  for candidate_index, entry in ipairs(self.effects) do
    if entry == old_entry then
      index = candidate_index
      break
    end
  end
  if index == nil then
    return nil, reload_error("effect replacement target is unavailable", { stage = "target" })
  end
  local candidate_entry, candidate_error = effect_methods(candidate)
  if not candidate_entry then
    local failure = reload_from("manifest", candidate_error)
    add_diagnostic(self, old_entry, "replace", failure)
    return nil, failure
  end
  if candidate_entry.manifest.id ~= old_entry.manifest.id then
    local failure = reload_failure("effect replacement id does not match target", {
      expected = old_entry.manifest.id,
      provided = candidate_entry.manifest.id,
      stage = "manifest",
    })
    add_diagnostic(self, old_entry, "replace", failure)
    return nil, failure
  end
  local compatible, compatible_error = capability_compatible(self, candidate_entry)
  if not compatible then
    local failure = reload_from("capability", compatible_error)
    add_diagnostic(self, old_entry, "replace", failure)
    return nil, failure
  end
  local values, migrations_or_error = migration_values(old_entry, candidate_entry)
  if not values then
    local failure = reload_from("parameters", migrations_or_error)
    add_diagnostic(self, old_entry, "replace", failure)
    return nil, failure
  end
  local configured, configure_error = configure_parameters(candidate_entry, values)
  if not configured then
    local failure = reload_from("parameters", configure_error)
    add_diagnostic(self, old_entry, "replace", failure)
    return nil, failure
  end
  local initialised_random, random_error = initialise_random(self, candidate_entry)
  if not initialised_random then
    local failure = reload_from("random", random_error)
    add_diagnostic(self, old_entry, "replace", failure)
    return nil, failure
  end
  candidate_entry.disabled_reason = old_entry.disabled_reason
  candidate_entry.enabled = old_entry.enabled
  candidate_entry.metadata = copy_metadata(old_entry.metadata)
  if request.source_identity then
    candidate_entry.metadata.source_identity = request.source_identity
  end
  candidate_entry.reload_generation = old_entry.reload_generation + 1
  if candidate_entry.hooks.init then
    local initialised, init_error = call_hook(self, candidate_entry, "init")
    if not initialised then
      local failure = reload_from("init", init_error)
      add_diagnostic(self, old_entry, "replace", failure)
      return nil, failure
    end
  end
  candidate_entry.initialised = true
  self.effects[index] = candidate_entry
  for _, migration in ipairs(migrations_or_error) do
    add_reload_migration(self, candidate_entry, migration)
  end
  shutdown_entry(self, old_entry)
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
  if self.canvas_frame == nil then
    local frame, frame_error = self:begin_canvas_frame({
      terminal = self.terminal,
      viewport = self.viewport,
    })
    if not frame then
      return nil, frame_error
    end
  end
  for _, entry in ipairs(self.canvas_frame.entries) do
    invoke_canvas(self, entry, "before_canvas", "before")
  end
  return true
end

function host_mt:after_canvas()
  if self.canvas_frame == nil then
    local frame, frame_error = self:begin_canvas_frame({
      terminal = self.terminal,
      viewport = self.viewport,
    })
    if not frame then
      return nil, frame_error
    end
  end
  for _, entry in ipairs(self.canvas_frame.entries) do
    invoke_canvas(self, entry, "after_canvas", "after")
  end
  self:end_canvas_frame()
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
      disabled_reason = entry.disabled_reason,
      id = entry.manifest.id,
      initialised = entry.initialised,
      metadata = copy_metadata(entry.metadata or {}),
      reload_generation = entry.reload_generation or 0,
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
