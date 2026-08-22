local Assert = require("tests.assert")

local function source()
  local root = os.getenv("KIWI_ROOT") or "."
  local file = assert(io.open(root .. "/src/kiwi/renderer/terminal.wgsl", "r"))
  local value = file:read("*a")
  file:close()
  return value
end

return {
  glyph_shader_preserves_grayscale_coverage_for_alpha_blending = function()
    local shader = source()
    Assert.truthy(shader:find("if (coverage <= 0.0) { discard; }", 1, true) ~= nil)
    Assert.truthy(shader:find("return vec4<f32>(color.rgb, color.a * coverage);", 1, true) ~= nil)
    Assert.truthy(shader:find("coverage < 0.30", 1, true) == nil)
  end,
  cursor_shader_uses_the_terminal_cursor_colour_uniform = function()
    local shader = source()
    Assert.truthy(shader:find("result.fg = srgb_to_surface(vec4<f32>(frame.cursor_red, frame.cursor_green, frame.cursor_blue, frame.cursor_alpha));", 1, true) ~= nil)
  end,
}
