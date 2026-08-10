local Context = require("kiwi.gpu.context")
local FontSystem = require("kiwi.font.system")
local Metrics = require("kiwi.diagnostics.metrics")
local Renderer = require("kiwi.renderer.renderer")
local Synthetic = require("kiwi.terminal.synthetic")
local Window = require("kiwi.platform.window")

local Demo = {}

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value >= 0 and value or fallback
end

function Demo.run()
  local window = Window.new(1600, 960, "Kiwi M1 synthetic renderer laboratory")
  local context
  local renderer
  local font
  local ok, result = xpcall(function()
    context = Context.new(window, { gpu_timestamps = os.getenv("KIWI_GPU_TIMESTAMPS") == "1" })
    local model = Synthetic.new(number_from_env("KIWI_SEED", 0x4b495749), 160, 50)
    font = FontSystem.new({ pixel_height = number_from_env("KIWI_FONT_PX", 20) })
    renderer = Renderer.new(context, font, model, { pass_budgets_enabled = os.getenv("KIWI_PASS_BUDGETS") == "1" })
    local metrics = Metrics.new(context, font, model)
    local scenario = os.getenv("KIWI_SCENARIO") or "typing"
    local max_frames = number_from_env("KIWI_MAX_FRAMES", 0)
    local next_frame = window:time()
    local next_scenario = next_frame + 0.20
    local tick = 0
    io.stdout:write(string.format("Kiwi M2 demo: Unicode=17.0 grid=%dx%d primary=%s\n", model.columns, model.rows, font.font_path))
    while not window:should_close() do
      local now = window:time()
      if now < next_frame then
        window:wait_events(math.min(next_frame - now, 0.050))
      end
      window:poll_events()
      now = window:time()
      if now >= next_frame then
        if now >= next_scenario then
          tick = tick + 1
          Synthetic.apply(model, scenario, tick)
          next_scenario = now + 0.20
        end
        local frame_start = now
        local prepare_start = window:time()
        renderer:update_model(model)
        local prepare_elapsed = window:time() - prepare_start
        local rendered, reason = renderer:render(model, now, window.debug_dirty, window.debug_boundaries)
        if not rendered and reason ~= "zero-sized drawable" then
          context.window.resized = true
        end
        metrics:record(window:time() - frame_start, prepare_elapsed, renderer)
        if window.debug_metrics then
          metrics:report(now)
        end
        next_frame = now + 1 / 30
        if max_frames > 0 and metrics.frame_number >= max_frames then
          break
        end
      end
    end
  end, debug.traceback)
  if renderer then renderer:destroy() end
  if font then font:destroy() end
  if context then context:destroy() end
  window:destroy()
  if not ok then error(result) end
end

return Demo
