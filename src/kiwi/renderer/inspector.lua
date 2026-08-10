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

function Inspector.build(renderer, selected)
  local registry = renderer.pass_registry
  local timing = timing_by_name(renderer.diagnostics.pass_cpu)
  local passes = {}
  for index, pass in ipairs(registry.passes) do
    local sample = timing[pass.name]
    passes[index] = {
      name = pass.name,
      order = pass.order,
      reads = copy_names(pass.reads),
      writes = copy_names(pass.writes),
      after = copy_names(pass.after),
      lifecycle = pass.lifecycle or registry.state,
      selected = selected == pass.name,
      cpu = sample and { prepare_ms = sample.prepare_ms, encode_ms = sample.encode_ms } or { unavailable = true },
    }
  end
  return {
    enabled = true,
    selected_pass = selected,
    registry_state = registry.state,
    error = registry.last_error,
    invalidation = renderer:invalidation_snapshot(),
    gpu_timing = renderer.context.timestamp_query_supported and "unavailable (M3 GPU timestamp readback is not enabled)" or "unavailable (adapter lacks timestamp-query feature)",
    passes = passes,
  }
end

function Inspector.format(view)
  local lines = { string.format("render-inspector state=%s selected=%s gpu=%s", view.registry_state, view.selected_pass or "none", view.gpu_timing) }
  if view.error then lines[#lines + 1] = "error=" .. view.error end
  lines[#lines + 1] = "invalidation=" .. table.concat(view.invalidation.reasons, ",") .. " deadline=" .. tostring(view.invalidation.deadline)
  for _, pass in ipairs(view.passes) do
    local cpu = pass.cpu.unavailable and "cpu=unavailable" or string.format("cpu=%.3f/%.3fms", pass.cpu.prepare_ms, pass.cpu.encode_ms)
    lines[#lines + 1] = string.format("pass=%s order=%d state=%s reads=%s writes=%s after=%s %s", pass.name, pass.order, pass.lifecycle, table.concat(pass.reads, ","), table.concat(pass.writes, ","), table.concat(pass.after, ","), cpu)
  end
  return table.concat(lines, "\n")
end

return Inspector
