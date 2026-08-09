local Assert = require("tests.assert")
local Renderer = require("kiwi.renderer.renderer")
local State = require("kiwi.terminal.state")

return {
  renderer_uses_question_mark_for_missing_atlas_glyphs_without_changing_state = function()
    local atlas = {
      get = function(_, glyph)
        if glyph == "?" then
          return { u0 = 0, v0 = 0, u1 = 1, v1 = 1 }
        end
      end,
    }
    local glyph, glyph_key = Renderer.select_glyph(atlas, "€")
    Assert.equal(glyph_key, "?")
    Assert.truthy(glyph ~= nil)
    local state = State.new(2, 1)
    state:write_codepoint("€")
    Assert.equal(state:get(0, 0).glyph, "€")
  end,
}
