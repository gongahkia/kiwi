-- Native GPU readback; kept separate from headless model tests.
local Context = require("kiwi.gpu.context")
local Host = require("kiwi.app.glfw_host")
local Window = require("kiwi.platform.window")
local Font = require("kiwi.font.system")
local Renderer = require("kiwi.renderer.renderer")
local Compositor = require("kiwi.renderer.compositor")
local Terminal = require("kiwi.session.terminal")
local window, context, font, renderer
local ok, message = xpcall(function()
  window = Window.new(320, 180, "Kiwi appearance verification")
  context = Context.new(Host, window, { framebuffer_capture = true, background_opacity = 0.5 })
  assert(context.transparency_supported, "native host has no transparent surface")
  font = Font.new({ pixel_height = 18 })
  local terminal = Terminal.new({ columns = 20, rows = 4 })
  terminal:write("\27[?25l\27[97m████ Kiwi opacity")
  local state = Terminal.state(terminal)
  local compositor = Compositor.new(context)
  local function capture(opacity)
    if renderer then renderer:destroy(); renderer = nil end
    renderer = Renderer.new(context, font, state, { background_opacity = opacity, scrollbar_policy = "never" })
    context.framebuffer_samples = {}
    local after_frame = compositor.frame
    local deadline = window:time() + 5
    repeat
      window:poll_events()
      compositor:render({ { renderer = renderer, model = state,
        viewport = { x = 0, y = 0, width = context.width - 10, height = context.height - 10 } } }, window:time())
      window:wait_events(0.01)
      context:poll_framebuffer_capture()
      local sample = context.framebuffer_samples[#context.framebuffer_samples]
      if sample and sample.frame > after_frame then return sample end
    until window:time() >= deadline
    error("appearance framebuffer readback timed out")
  end
  local opaque = capture(1)
  assert(opaque.fully_opaque_pixels == context.width * context.height, "opaque configuration left transparent pixels")
  local translucent = capture(0.5)
  assert(translucent.fully_opaque_pixels > 50, "text lost its opaque foreground")
  assert(translucent.fully_opaque_pixels < opaque.fully_opaque_pixels / 2, "terminal background did not become translucent")
  local transparent = capture(0)
  assert(transparent.transparent_pixels > context.width * context.height / 2, "zero opacity left a visible background")
  assert(transparent.fully_opaque_pixels > 50, "zero background opacity made text disappear")
  local restored = capture(1)
  assert(restored.fully_opaque_pixels == opaque.fully_opaque_pixels, "opacity did not return to fully opaque")
  print("Appearance GPU smoke passed: background alpha 1/0.5/0/1, opaque text, and window gutters.")
end, debug.traceback)
if renderer then renderer:destroy() end
if font then font:destroy() end
if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
