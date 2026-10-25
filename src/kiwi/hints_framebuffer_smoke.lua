local Context = require("kiwi.gpu.context")
local Host = require("kiwi.app.glfw_host")
local Window = require("kiwi.platform.window")
local Font = require("kiwi.font.system")
local Renderer = require("kiwi.renderer.renderer")
local Compositor = require("kiwi.renderer.compositor")
local Terminal = require("kiwi.session.terminal")
local window, context, font, renderer
local ok, message = xpcall(function()
  window = Window.new(400, 200, "Kiwi URL hints verification")
  context = Context.new(Host, window, { framebuffer_capture = true, framebuffer_expected_rgb = "235,203,139" })
  font = Font.new({ pixel_height = 18, atlas = { width = 128, height = 128, max_entries = 1 } })
  local terminal = Terminal.new({ columns = 20, rows = 4 })
  terminal:write("\27[?25l\27[8mhttps://example.test")
  local state, compositor = Terminal.state(terminal), Compositor.new(context)
  renderer = Renderer.new(context, font, state, { scrollbar_policy = "never" })
  local function capture()
    context.framebuffer_samples = {}
    local after, deadline = compositor.frame, window:time() + 5
    repeat
      window:poll_events()
      renderer:update_model(state)
      compositor:render({ { renderer = renderer, model = state,
        viewport = { x = 0, y = 0, width = context.width, height = context.height } } }, window:time())
      window:wait_events(0.01); context:poll_framebuffer_capture()
      local sample = context.framebuffer_samples[#context.framebuffer_samples]
      if sample and sample.frame > after then return sample end
    until window:time() >= deadline
    error("hint framebuffer readback timed out")
  end
  assert(capture().expected_rgb_pixels == 0)
  state:hints_begin(); while state:hints_pending() do state:hints_step() end
  assert(#state.hints.matches == 1)
  renderer:invalidate("search")
  local sample = capture()
  local area = context.width * context.height / (state.columns * state.rows)
  assert(sample.expected_rgb_pixels > area * 0.55 and sample.expected_rgb_pixels < area * 0.90,
    "hint badge background/letter coverage is incorrect: " .. sample.expected_rgb_pixels)
  assert(renderer.hint_count == 1)
  state.hints:append(state, "a"); renderer:invalidate("search")
  assert(capture().expected_rgb_pixels == 0, "chosen label did not change colour")
  state.hints:backspace(); renderer:invalidate("search")
  assert(capture().expected_rgb_pixels == sample.expected_rgb_pixels, "label did not return after Backspace")
  terminal:write("x"); renderer:invalidate("terminal")
  assert(capture().expected_rgb_pixels == 0 and renderer.hint_count == 0, "stale URL label remained visible")
  print("Hints GPU smoke passed: opaque letter badge with a saturated font cache, chosen colour, Backspace and stale-target removal.")
end, debug.traceback)
if renderer then renderer:destroy() end
if font then font:destroy() end
if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
