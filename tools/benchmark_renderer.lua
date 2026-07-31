package.path = table.concat({
  "./?.lua",
  "./src/?.lua",
  "./src/?/init.lua",
  "./tests/?.lua",
  "./tests/?/init.lua",
  package.path,
}, ";")

local BenchmarkPolicy = require("renderer.benchmark_policy")
local CRT = require("effects.crt")
local Effect = require("effects.effect")
local Host = require("effects.host")
local Kinetic = require("effects.kinetic")
local ContinuousOutput = require("fixtures.renderer.continuous_output")
local Font = require("fixtures.renderer.font")
local Renderer = require("renderer.renderer")
local Baselines = require("benchmarks.baselines")

local frame_delta_us = 16667

local fixture_definitions = {
  { id = "clean", kind = "clean" },
  { id = "crt", kind = "crt" },
  { id = "kinetic", kind = "kinetic" },
  { id = "combined", kind = "combined" },
  { id = "effects_disabled", kind = "effects_disabled" },
  { id = "quarantined", kind = "quarantined" },
}

local grids = {
  { columns = 120, rows = 40 },
  { columns = 240, rows = 80 },
}

local function positive_integer(value, name)
  local number = tonumber(value)
  if not number or number % 1 ~= 0 or number < 1 then
    io.stderr:write(name .. " must be a positive integer\n")
    os.exit(2)
  end
  return number
end

local function usage()
  io.stderr:write(
    "usage: benchmark_renderer.lua [frames] [--fixtures all|clean,crt] [--grid all|120x40|240x80] [--frames n] [--warmup n] [--samples n] [--no-check]\n"
  )
  os.exit(2)
end

local function options(arguments)
  local result = {
    check = true,
    fixtures = "all",
    grid = "all",
    frames = 300,
    samples = 5,
    warmup = 60,
  }
  local index = 1
  while index <= #arguments do
    local value = arguments[index]
    if value == "--fixtures" then
      index = index + 1
      result.fixtures = arguments[index] or usage()
    elseif value == "--grid" then
      index = index + 1
      result.grid = arguments[index] or usage()
    elseif value == "--frames" then
      index = index + 1
      result.frames = positive_integer(arguments[index], "frames")
    elseif value == "--warmup" then
      index = index + 1
      result.warmup = positive_integer(arguments[index], "warmup")
    elseif value == "--samples" then
      index = index + 1
      result.samples = positive_integer(arguments[index], "samples")
    elseif value == "--no-check" then
      result.check = false
    elseif value:sub(1, 2) ~= "--" and index == 1 then
      result.frames = positive_integer(value, "frames")
    else
      usage()
    end
    index = index + 1
  end
  return result
end

local function selected_grids(selection)
  if selection == "all" then
    return grids
  end
  for _, grid in ipairs(grids) do
    if selection == grid.columns .. "x" .. grid.rows then
      return { grid }
    end
  end
  io.stderr:write("unknown benchmark grid: " .. selection .. "\n")
  os.exit(2)
end

local function selected_definitions(selection)
  if selection == "all" then
    return fixture_definitions
  end
  local known = {}
  for _, definition in ipairs(fixture_definitions) do
    known[definition.id] = definition
  end
  local result = {}
  for id in selection:gmatch("[^,]+") do
    if known[id] == nil then
      io.stderr:write("unknown benchmark fixture: " .. id .. "\n")
      os.exit(2)
    end
    result[#result + 1] = known[id]
  end
  if #result == 0 then
    usage()
  end
  return result
end

local function graphics()
  local counters = { shader_compilations = 0, temporary_canvases = 0 }
  local value = { counters = counters }
  function value.newFont()
    return Font.new()
  end
  function value.getBlendMode()
    return "alpha", "alphamultiply"
  end
  function value.getCanvas()
    return nil
  end
  function value.getColor()
    return 1, 1, 1, 1
  end
  function value.getDepthMode()
    return false, false
  end
  function value.getFont()
    return nil
  end
  function value.getLineStyle()
    return "rough"
  end
  function value.getLineWidth()
    return 1
  end
  function value.getMeshCullMode()
    return "none"
  end
  function value.getPointSize()
    return 1
  end
  function value.getScissor()
    return nil
  end
  function value.getShader()
    return nil
  end
  function value.getStencilTest()
    return nil
  end
  function value.line() end
  function value.pop() end
  function value.print() end
  function value.push() end
  function value.rectangle() end
  function value.setBlendMode() end
  function value.setCanvas() end
  function value.setColor() end
  function value.setDepthMode() end
  function value.setFont() end
  function value.setLineStyle() end
  function value.setLineWidth() end
  function value.setMeshCullMode() end
  function value.setPointSize() end
  function value.setScissor() end
  function value.setShader() end
  function value.setStencilTest() end
  return value
end

local function failing_effect()
  return assert(Effect.new({
    api_version = 1,
    capabilities = { "frame_update", "lifecycle" },
    determinism = "deterministic",
    id = "benchmark.quarantined",
    parameters = {},
    version = "0.1.0",
  }, {
    update = function()
      error("fixture failure")
    end,
  }))
end

local function effects_for(kind)
  if kind == "clean" then
    return nil
  end
  if kind == "crt" then
    return { assert(CRT.new({ bloom = 0.2, intensity = 0.35, persistence = 0.2 })) }
  end
  if kind == "kinetic" then
    return { assert(Kinetic.new({ decay = 0.6, intensity = 0.35, max_offset = 0.25 })) }
  end
  if kind == "combined" or kind == "effects_disabled" then
    return {
      assert(CRT.new({ bloom = 0.2, intensity = 0.35, persistence = 0.2 })),
      assert(Kinetic.new({ decay = 0.6, intensity = 0.35, max_offset = 0.25 })),
    }
  end
  return { failing_effect() }
end

local function resource_counts(run)
  local host_status = run.host and run.host:status() or { effects = {} }
  local canvas_stats = run.renderer.canvas_runtime and run.renderer.canvas_runtime:stats()
    or {
      allocations = 0,
    }
  return {
    canvases = canvas_stats.allocations,
    effect_instances = #host_status.effects,
    fonts = run.renderer.font and 1 or 0,
    shader_compilations = run.graphics.counters.shader_compilations,
    shaders = 0,
    temporary_canvases = run.graphics.counters.temporary_canvases,
  }
end

local function growth(start, finish)
  local result = {}
  for field, value in pairs(finish) do
    result[field] = math.max(0, value - start[field])
  end
  return result
end

local function build(definition, grid)
  local effect_list = effects_for(definition.kind)
  local host
  if effect_list then
    host = assert(Host.new(effect_list, {
      headless = false,
      random_seed = 31337,
      terminal = { columns = grid.columns, rows = grid.rows },
      viewport = { height = grid.rows * 16, width = grid.columns * 8 },
    }))
    if definition.kind == "effects_disabled" then
      for _, status in ipairs(host:status().effects) do
        assert(host:disable(status.id))
      end
    end
  end
  local fixture = ContinuousOutput.new(grid)
  local graphics_value = graphics()
  local renderer = assert(Renderer.new({ effect_host = host }))
  assert(renderer:load_font(graphics_value))
  local elapsed_us = 0
  local function frame()
    elapsed_us = elapsed_us + frame_delta_us
    if host then
      assert(host:update(frame_delta_us))
      if definition.kind ~= "quarantined" and definition.kind ~= "effects_disabled" then
        assert(host:emit("output", { bytes = "0123456789abcdef" }, elapsed_us))
      end
    end
    local snapshot, damage = fixture:advance()
    assert(renderer:draw(snapshot, damage))
  end
  return {
    frame = frame,
    graphics = graphics_value,
    host = host,
    renderer = renderer,
  }
end

local function median(values)
  local copy = {}
  for index, value in ipairs(values) do
    copy[index] = value
  end
  table.sort(copy)
  local middle = math.floor((#copy + 1) / 2)
  if #copy % 2 == 1 then
    return copy[middle]
  end
  return (copy[middle] + copy[middle + 1]) / 2
end

local function measure(definition, grid, settings)
  local samples = {}
  local final_counts
  local quarantined = false
  local allocation_frames = 1
  for _ = 1, settings.samples do
    local run = build(definition, grid)
    for _ = 1, settings.warmup do
      run.frame()
    end
    if definition.kind == "quarantined" then
      quarantined = not run.host:status().effects[1].enabled
    end
    collectgarbage("collect")
    local start_resources = resource_counts(run)
    local start_seconds = os.clock()
    for _ = 1, settings.frames do
      run.frame()
    end
    local elapsed_seconds = os.clock() - start_seconds
    collectgarbage("collect")
    collectgarbage("stop")
    local start_heap = collectgarbage("count")
    for _ = 1, allocation_frames do
      run.frame()
    end
    local finish_heap = collectgarbage("count")
    collectgarbage("restart")
    collectgarbage("collect")
    local finish_resources = resource_counts(run)
    samples[#samples + 1] = {
      bytes_per_frame = math.max(0, (finish_heap - start_heap) * 1024) / allocation_frames,
      frame_time_us = elapsed_seconds * 1000000 / settings.frames,
      fps = elapsed_seconds > 0 and settings.frames / elapsed_seconds or 0,
      resource_growth = growth(start_resources, finish_resources),
    }
    final_counts = finish_resources
  end
  local frame_times = {}
  local bytes = {}
  local fps = {}
  local resource_growth = {
    canvases = 0,
    effect_instances = 0,
    fonts = 0,
    shader_compilations = 0,
    shaders = 0,
    temporary_canvases = 0,
  }
  for index, sample in ipairs(samples) do
    frame_times[index] = sample.frame_time_us
    bytes[index] = sample.bytes_per_frame
    fps[index] = sample.fps
    for field, value in pairs(sample.resource_growth) do
      resource_growth[field] = math.max(resource_growth[field], value)
    end
  end
  return {
    bytes_per_frame = median(bytes),
    allocation_frames = allocation_frames,
    frame_time_us = median(frame_times),
    fps = median(fps),
    quarantined = quarantined,
    resources = resource_growth,
    retained = final_counts,
  }
end

local function environment_signature()
  return table.concat({
    "fixture_graphics=v1",
    "font=fixture-font-v1",
    "luajit=" .. jit.version,
    "platform=" .. jit.os .. "/" .. jit.arch,
  }, ";")
end

local function baseline_for(signature, fixture_id, settings)
  local environment = Baselines.environments[signature]
  local baseline = environment and environment.fixtures[fixture_id] or nil
  if baseline == nil then
    return nil, environment, "missing_fixture"
  end
  for _, field in ipairs({ "frames", "samples", "warmup" }) do
    if baseline[field] ~= settings[field] then
      return nil, environment, "incomparable_configuration"
    end
  end
  return baseline, environment, "matched"
end

local function print_result(
  definition,
  grid,
  settings,
  result,
  baseline,
  environment,
  baseline_status,
  clean
)
  local fixture_id = definition.id .. "_" .. grid.columns .. "x" .. grid.rows
  print("fixture=" .. fixture_id)
  print("frames=" .. settings.frames)
  print("warmup_frames=" .. settings.warmup)
  print("samples=" .. settings.samples)
  print("allocation_window_frames=" .. result.allocation_frames)
  print(string.format("median_frame_time_us=%.4f", result.frame_time_us))
  print(string.format("median_frames_per_second=%.2f", result.fps))
  print(string.format("median_gc_stopped_bytes_per_frame=%.2f", result.bytes_per_frame))
  for _, field in ipairs({
    "canvases",
    "effect_instances",
    "fonts",
    "shaders",
    "shader_compilations",
    "temporary_canvases",
  }) do
    print("retained_" .. field .. "=" .. result.retained[field])
    print("steady_state_" .. field .. "_growth=" .. result.resources[field])
  end
  print("quarantined=" .. tostring(result.quarantined))
  if clean then
    print(
      string.format(
        "relative_frame_time_percent=%.2f",
        result.frame_time_us / clean.frame_time_us * 100
      )
    )
    print(
      string.format(
        "relative_bytes_per_frame_percent=%.2f",
        result.bytes_per_frame / clean.bytes_per_frame * 100
      )
    )
  end
  if environment == nil then
    print("baseline=unmatched_environment")
    return true
  end
  if baseline == nil then
    print("baseline=" .. baseline_status)
    return true
  end
  local comparison = assert(BenchmarkPolicy.compare(result, baseline))
  print("baseline_reason=" .. environment.reason)
  print("baseline=matched")
  print("comparison=" .. (comparison.passed and "pass" or "fail"))
  if not comparison.passed then
    print("regressions=" .. table.concat(comparison.reasons, ","))
  end
  return comparison.passed
end

local settings = options(arg)
local signature = environment_signature()
local passed = true
local clean_results = {}
print("renderer benchmark")
print("environment_signature=" .. signature)
for _, definition in ipairs(selected_definitions(settings.fixtures)) do
  for _, grid in ipairs(selected_grids(settings.grid)) do
    local fixture_id = definition.id .. "_" .. grid.columns .. "x" .. grid.rows
    local baseline, environment, baseline_status = baseline_for(signature, fixture_id, settings)
    local result = measure(definition, grid, settings)
    local grid_id = grid.columns .. "x" .. grid.rows
    if definition.id == "clean" then
      clean_results[grid_id] = result
    end
    if
      not print_result(
        definition,
        grid,
        settings,
        result,
        baseline,
        environment,
        baseline_status,
        clean_results[grid_id]
      )
    then
      passed = false
    end
  end
end
if settings.check and not passed then
  os.exit(1)
end
