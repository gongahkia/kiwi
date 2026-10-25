local Config = require("kiwi.config")
local Environment = require("kiwi.bench.environment")
local Font = require("kiwi.font.system")
local Json = require("kiwi.bench.json")
local Metrics = require("kiwi.bench.process_metrics")
local PreparedFrame = require("kiwi.renderer.prepared_frame")
local Reload = require("kiwi.app.configuration_reload")
local Stats = require("kiwi.bench.stats")
local Terminal = require("kiwi.session.terminal")
local Workspace = require("kiwi.session.workspace")

local Bench = {}

local function configuration(history, font_size, background)
  return Config.parse(string.format("scrollback-limit = %d\nfont-size = %d\nbackground = %s\n", history, font_size, background))
end

local function new_font(configuration)
  return Font.new({ pixel_height = configuration.font_size, primary_family = configuration.font_family })
end

local function new_renderer(font, state)
  local prepared = PreparedFrame.new(font, state)
  local ok, message = pcall(function() prepared:commit_model(prepared:prepare_model(state)) end)
  if not ok then prepared:destroy(); error(message) end
  return { invalidate = function() end, destroy = function() prepared:destroy() end }
end

function Bench.run(options)
  options = options or {}
  local history, iterations = options.history_lines or 2000, options.iterations or 5
  assert(history >= 0 and history <= 20000 and history % 1 == 0, "reload benchmark history must be 0 through 20000")
  assert(iterations >= 1 and iterations <= 100 and iterations % 1 == 0, "reload benchmark iterations must be 1 through 100")
  local current = configuration(history, 18, "#20242b")
  local font = new_font(current)
  local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = history } })
  local state = Terminal.state(terminal)
  for line = 1, history + state.rows do
    terminal:write(string.format("%06d build output: Café 界 Ω -- retained configuration history\r\n", line))
  end
  local session = { terminal = terminal, metrics = { font = font }, renderer = new_renderer(font, state) }
  local workspace = Workspace.new(); workspace:new_tab(session)
  local result = { history_lines = history, columns = state.columns, rows = state.rows, iterations = iterations, cases = {} }
  local ok, message = pcall(function()
    local baseline_rss = assert(Metrics.resident_kib(), "resident memory observation unavailable")
    for _, mode in ipairs({ "palette", "font_resize" }) do
      local candidate = configuration(history, mode == "palette" and 18 or 20, "#121f34")
      local settings = {
        current = current, candidate = candidate, font = font, workspace = workspace,
        dimensions = function(value)
          return math.floor(80 * font.cell_width / value.cell_width), math.floor(24 * font.cell_height / value.cell_height)
        end,
        new_font = new_font, new_renderer = new_renderer,
      }
      -- Warm native font/raster paths before sampling. Each sample still builds
      -- its complete candidate state/resources and then rejects it.
      local warmup = assert(Reload.prepare(settings)); warmup:abort(); warmup = nil
      collectgarbage("collect")
      local heap_before, rss_before = collectgarbage("count"), Metrics.resident_kib()
      local peak_heap, peak_rss = heap_before, rss_before
      local cpu, wall = {}, {}
      for iteration = 1, iterations do
        local start_wall, start_cpu = Metrics.monotonic_seconds(), os.clock()
        local plan = assert(Reload.prepare(settings))
        cpu[iteration] = (os.clock() - start_cpu) * 1000
        wall[iteration] = (Metrics.monotonic_seconds() - start_wall) * 1000
        peak_heap = math.max(peak_heap, collectgarbage("count"))
        peak_rss = math.max(peak_rss, Metrics.resident_kib())
        assert(#plan:abort() == 0)
        plan = nil
        collectgarbage("collect")
        assert(Terminal.state(terminal) == state and state.columns == 80 and state.rows == 24)
        assert(state.scrollback:size() == history, "rejected reload changed retained history")
      end
      local retained_heap = collectgarbage("count") - heap_before
      assert(retained_heap < 4 * 1024, "repeated rejected reloads retained more than 4 MiB of Lua state")
      result.cases[#result.cases + 1] = {
        mode = mode, cpu_ms = Stats.summary(cpu), wall_ms = Stats.summary(wall),
        memory = { baseline_rss_kib = baseline_rss, sampled_peak_rss_kib = peak_rss,
          rss_kib_delta = Metrics.resident_kib() - rss_before, sampled_peak_rss_kib_delta = peak_rss - rss_before,
          peak_heap_kib_delta = peak_heap - heap_before, retained_heap_kib_delta = retained_heap },
      }
    end
  end)
  session.renderer:destroy(); font:destroy(); terminal:close()
  assert(ok, message)
  return result
end

function Bench.main()
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local iterations = tonumber(os.getenv("KIWI_RELOAD_ITERATIONS")) or 5
  local requested = os.getenv("KIWI_RELOAD_HISTORY")
  local results = {}
  for _, history in ipairs(requested and { assert(tonumber(requested)) } or { 0, 2000, 10000 }) do
    local result = Bench.run({ history_lines = history, iterations = iterations })
    results[#results + 1] = result
    for _, sample in ipairs(result.cases) do
      print(string.format("reload history=%d mode=%s wall-p95=%.1fms cpu-p95=%.1fms heap-peak=%.1fMiB heap-retained=%.1fKiB rss-peak=%.1fMiB",
        history, sample.mode, sample.wall_ms.p95, sample.cpu_ms.p95, sample.memory.peak_heap_kib_delta / 1024,
        sample.memory.retained_heap_kib_delta, sample.memory.sampled_peak_rss_kib / 1024))
    end
  end
  local output = "bench/results/" .. timestamp .. "-configuration-reload.json"
  local file = assert(io.open(output, "wb"))
  file:write(Json.encode({ schema_version = 1, benchmark = "configuration reload staging",
    scope = "CPU state clone/reflow, native font resolution, shaping and buffer packing; excludes GPU allocation/upload/presentation and PTY resize; sampled RSS is not OS high-water RSS",
    metadata = Environment.collect(timestamp, iterations, 1), results = results }), "\n")
  file:close()
  print("machine-readable result: " .. output)
end

if ... == nil then Bench.main() end
return Bench
