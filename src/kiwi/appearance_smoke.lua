-- Native GPU readback; kept separate from headless model tests.
local Context = require("kiwi.gpu.context")
local Host = require("kiwi.app.glfw_host")
local Window = require("kiwi.platform.window")
local Font = require("kiwi.font.system")
local Renderer = require("kiwi.renderer.renderer")
local Compositor = require("kiwi.renderer.compositor")
local Terminal = require("kiwi.session.terminal")
local window, context, font, renderer, second_renderer
local ok, message = xpcall(function()
  window = Window.new(320, 180, "Kiwi appearance verification")
  context = Context.new(Host, window, { framebuffer_capture = true, background_opacity = 0.5 })
  assert(context.transparency_supported, "native host has no transparent surface")
  font = Font.new({ pixel_height = 18 })
  local terminal = Terminal.new({ columns = 20, rows = 4 })
  terminal:write("\27[?25l\27[97m████ Kiwi opacity")
  local state = Terminal.state(terminal)
  local second = Terminal.new({ columns = 20, rows = 4 })
  second:write("\27[?25l\27[97m████ Second pane")
  local second_state = Terminal.state(second)
  local compositor = Compositor.new(context)
  local function readback()
    context.framebuffer_samples = {}
    local after_frame = compositor.frame
    local deadline = window:time() + 5
    repeat
      window:poll_events()
      local half = math.floor(context.width / 2)
      compositor:render({
        { renderer = renderer, model = state,
          viewport = { x = 0, y = 0, width = half - 5, height = context.height - 10 } },
        { renderer = second_renderer, model = second_state,
          viewport = { x = half + 5, y = 0, width = context.width - half - 5, height = context.height - 10 } },
      }, window:time())
      window:wait_events(0.01)
      context:poll_framebuffer_capture()
      local sample = context.framebuffer_samples[#context.framebuffer_samples]
      if sample and sample.frame > after_frame then return sample end
    until window:time() >= deadline
    error("appearance framebuffer readback timed out")
  end
  local function capture(opacity, source)
    if renderer then renderer:destroy(); renderer = nil end
    if second_renderer then second_renderer:destroy(); second_renderer = nil end
    renderer = Renderer.new(context, font, state, { background_opacity = opacity, scrollbar_policy = "never" })
    second_renderer = Renderer.new(context, font, second_state, { background_opacity = opacity, scrollbar_policy = "never" })
    context:set_effects(context:prepare_effects({ background_opacity = opacity, custom_shader_source = source }))
    return readback()
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
  local red = "fn kiwi_effect(color: vec4<f32>, uv: vec2<f32>, time: f32, resolution: vec2<f32>) -> vec4<f32> { return vec4<f32>(1.0, 0.0, 0.0, color.a); }"
  local red_frame = capture(0.5, red)
  assert(red_frame.red_dominant_pixels == context.width * context.height, "custom shader did not cover the complete window")
  assert(red_frame.fully_opaque_pixels < context.width * context.height / 2, "custom shader lost background transparency")
  local working = context.effect
  local valid = pcall(context.prepare_effects, context, { custom_shader_source = "invalid WGSL" })
  assert(not valid and context.effect == working, "invalid shader replaced the working pipeline")
  local retained = readback()
  assert(retained.red_dominant_pixels == context.width * context.height, "invalid shader damaged subsequent GPU output")
  window:set_size(420, 220)
  window:poll_events()
  local resized = readback()
  assert(resized.red_dominant_pixels == context.width * context.height, "effect did not resize with the surface")
  assert(context.effect.width == context.width and context.effect.height == context.height)
  for _, path in ipairs({ "examples/shaders/scanlines.wgsl", "examples/shaders/grayscale.wgsl" }) do
    local file = assert(io.open(path, "rb")); local source = file:read("*a"); file:close()
    assert(capture(1, source).fully_opaque_pixels == context.width * context.height, "sample shader changed opaque alpha")
  end
  print("Appearance GPU smoke passed: background alpha 1/0.5/0/1, opaque text, split panes, gutters, custom shader output, invalid-shader recovery, resize and sample effects.")
end, debug.traceback)
if renderer then renderer:destroy() end
if second_renderer then second_renderer:destroy() end
if font then font:destroy() end
if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
