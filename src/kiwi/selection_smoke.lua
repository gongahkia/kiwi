-- Actual GPU coverage, independent of CPU selection/copy assertions.
local Context = require("kiwi.gpu.context")
local Host = require("kiwi.app.glfw_host")
local Window = require("kiwi.platform.window")
local Font = require("kiwi.font.system")
local Renderer = require("kiwi.renderer.renderer")
local Compositor = require("kiwi.renderer.compositor")
local Terminal = require("kiwi.session.terminal")
local window, context, font, renderer
local ok, message = xpcall(function()
  window = Window.new(320, 160, "Kiwi selection verification")
  context = Context.new(Host, window, { framebuffer_capture = true })
  font = Font.new({ pixel_height = 18 })
  local terminal = Terminal.new({ columns = 8, rows = 4 })
  terminal:write("\27[?25l\27[8;30;40mabcdef\r\na中def\r\nabcdef")
  local state = Terminal.state(terminal)
  state:vi_toggle(); state.vi:motion(state, "top"); state.vi:motion(state, "first")
  state.vi:motion(state, "right", 2); state.vi:toggle_selection(state, "block")
  state.vi:motion(state, "down", 2); state.vi:motion(state, "right")
  assert(state:selection_text(100) == "cd\n中d\ncd", "block copy split a wide cell")
  -- Keep selection, suppress cursor overlay to measure its exact area.
  state.vi.active = false
  renderer = Renderer.new(context, font, state, { selection_color = "#ff0000ff", scrollbar_policy = "never" })
  local compositor = Compositor.new(context)
  local function capture()
    context.framebuffer_samples = {}
    local after, deadline = compositor.frame, window:time() + 5
    repeat
      window:poll_events()
      compositor:render({ { renderer = renderer, model = state,
        viewport = { x = 0, y = 0, width = context.width, height = context.height } } }, window:time())
      window:wait_events(0.01); context:poll_framebuffer_capture()
      local sample = context.framebuffer_samples[#context.framebuffer_samples]
      if sample and sample.frame > after then return sample end
    until window:time() >= deadline
    error("selection framebuffer readback timed out")
  end
  local rectangle = capture()
  local cell_pixels = context.width * context.height / (state.columns * state.rows)
  assert(rectangle.red_dominant_pixels == 7 * cell_pixels,
    "GPU block coverage differs from whole-cell rectangle: " .. rectangle.red_dominant_pixels)
  state:set_selection(0, 2, 2, 4); renderer:invalidate("selection")
  assert(capture().red_dominant_pixels == 18 * cell_pixels, "linear selection retained rectangular mode")
  state:clear_selection(); renderer:invalidate("selection")
  assert(capture().red_dominant_pixels == 0, "cleared selection remained visible")
  print("Selection GPU smoke passed: rectangular wide-cell coverage, linear range and cleared overlay.")
end, debug.traceback)
if renderer then renderer:destroy() end
if font then font:destroy() end
if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
