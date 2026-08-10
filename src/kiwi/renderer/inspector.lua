local Inspector = {}

local function copy_names(names)
  local copy = {}
  for index, name in ipairs(names or {}) do copy[index] = name end
  return copy
end

local function timing_by_name(snapshot)
  local result = {}
  for _, sample in ipairs(snapshot and snapshot.samples or {}) do result[sample.name] = sample end
  return result
end

local function budgets_by_name(snapshot)
  local result = {}
  for _, pass in ipairs(snapshot and snapshot.passes or {}) do result[pass.name] = pass end
  return result
end

local function map_count(values)
  local count = 0
  for _ in pairs(values or {}) do count = count + 1 end
  return count
end

function Inspector.build(renderer, selected)
  local registry = renderer.pass_registry
  local timing = timing_by_name(renderer.diagnostics.pass_cpu)
  local gpu_timing = renderer.diagnostics.gpu_timing or { enabled = false, status = renderer.context.timestamp_query_supported and "unavailable (timestamp instrumentation is disabled)" or "unavailable (adapter lacks timestamp-query feature)", samples = {} }
  local gpu = timing_by_name(gpu_timing)
  local pass_budgets = renderer.diagnostics.pass_budgets or { enabled = false, warnings = {}, passes = {} }
  local budgets = budgets_by_name(pass_budgets)
  local passes = {}
  for index, pass in ipairs(registry.passes) do
    local sample = timing[pass.name]
    local gpu_sample = gpu[pass.name]
    passes[index] = {
      name = pass.name,
      order = pass.order,
      reads = copy_names(pass.reads),
      writes = copy_names(pass.writes),
      after = copy_names(pass.after),
      lifecycle = pass.lifecycle or registry.state,
      selected = selected == pass.name,
      cpu = sample and { prepare_ms = sample.prepare_ms, encode_ms = sample.encode_ms } or { unavailable = true },
      gpu = gpu_sample and { ticks = gpu_sample.gpu_ticks, map_latency_ms = gpu_sample.map_latency_ms, frame = gpu_sample.frame } or { unavailable = true },
      budget = budgets[pass.name] or { name = pass.name, status = "unconfigured", declaration = {}, dimensions = {} },
    }
  end
  return {
    enabled = true,
    selected_pass = selected,
    registry_state = registry.state,
    error = registry.last_error,
    invalidation = renderer:invalidation_snapshot(),
    extensions = renderer.diagnostics.extensions or { enabled = true, diagnostics = {}, disabled = {} },
    gpu_timing = gpu_timing.status,
    budget_warnings = pass_budgets.warnings,
    passes = passes,
  }
end

function Inspector.format(view)
  local lines = { string.format("render-inspector state=%s selected=%s gpu=%s", view.registry_state, view.selected_pass or "none", view.gpu_timing) }
  if view.error then lines[#lines + 1] = "error=" .. view.error end
  lines[#lines + 1] = "invalidation=" .. table.concat(view.invalidation.reasons, ",") .. " deadline=" .. tostring(view.invalidation.deadline)
  lines[#lines + 1] = string.format("extensions=%s disabled=%d diagnostics=%d", view.extensions.enabled and "enabled" or "disabled", map_count(view.extensions.disabled), #view.extensions.diagnostics)
  for _, pass in ipairs(view.passes) do
    local cpu = pass.cpu.unavailable and "cpu=unavailable" or string.format("cpu=%.3f/%.3fms", pass.cpu.prepare_ms, pass.cpu.encode_ms)
    local gpu = pass.gpu.unavailable and "gpu=unavailable" or string.format("gpu=%d ticks/%.3fms", pass.gpu.ticks, pass.gpu.map_latency_ms)
    lines[#lines + 1] = string.format("pass=%s order=%d state=%s reads=%s writes=%s after=%s %s %s budget=%s", pass.name, pass.order, pass.lifecycle, table.concat(pass.reads, ","), table.concat(pass.writes, ","), table.concat(pass.after, ","), cpu, gpu, pass.budget.status)
  end
  return table.concat(lines, "\n")
end

return Inspector
