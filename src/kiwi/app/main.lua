local Window = require("kiwi.platform.window")
local Context = require("kiwi.gpu.context")
local Synthetic = require("kiwi.terminal.synthetic")
local FreeType = require("kiwi.font.freetype")
local Renderer = require("kiwi.renderer.renderer")
local Metrics = require("kiwi.diagnostics.metrics")

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value >= 0 and value or fallback
end

local function run()
  local window = Window.new(1600, 960, "Kiwi M0 renderer laboratory")
  local context
  local renderer
  local ok, result = xpcall(function()
    context = Context.new(window)
    local model = Synthetic.new(number_from_env("KIWI_SEED", 0x4b495749), 160, 50)
    local font = FreeType.rasterize({ pixel_height = number_from_env("KIWI_FONT_PX", 20) })
    renderer = Renderer.new(context, font, model)
    local metrics = Metrics.new(context, font, model)
    local scenario = os.getenv("KIWI_SCENARIO") or "typing"
    local max_frames = number_from_env("KIWI_MAX_FRAMES", 0)
    local frame_interval = 1 / 30
    local scenario_interval = 0.20
    local next_frame = window:time()
    local next_scenario = next_frame + scenario_interval
    local tick = 0

    io.stdout:write(string.format(
      "Kiwi M0: Vulkan adapter=%s vendor=%s grid=%dx%d atlas=%d glyphs (%dx%d)\n",
      context.adapter_info.device,
      context.adapter_info.vendor,
      model.columns,
      model.rows,
      font.atlas:glyph_count(),
      font.atlas.width,
      font.atlas.height
    ))

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
          next_scenario = now + scenario_interval
        end
        local frame_start = now
        local prepare_start = window:time()
        renderer:update_model(model)
        local prepare_elapsed = window:time() - prepare_start
        local rendered, reason = renderer:render(model, now, window.debug_dirty, window.debug_boundaries)
        if not rendered and reason ~= "zero-sized drawable" then
          if reason:sub(1, 17) == "native GPU error:" then
            error(reason)
          else
            context.window.resized = true
          end
        end
        local frame_elapsed = window:time() - frame_start
        metrics:record(frame_elapsed, prepare_elapsed, renderer)
        metrics:report(now)
        next_frame = now + frame_interval
        if max_frames > 0 and metrics.frame_number >= max_frames then
          break
        end
      end
    end
  end, debug.traceback)

  if renderer then
    renderer:destroy()
  end
  if context then
    context:destroy()
  end
  window:destroy()
  if not ok then
    error(result)
  end
end

run()
