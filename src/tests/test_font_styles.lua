local ffi = require("ffi")
local Assert = require("tests.assert")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local System = require("kiwi.font.system")

local function signature(bitmap)
  local sum, rows = 0, {}
  for row = 0, bitmap.height - 1 do
    rows[#rows + 1] = ffi.string(bitmap.buffer + row * bitmap.pitch, bitmap.width)
    for column = 0, bitmap.width - 1 do sum = sum + bitmap.buffer[row * bitmap.pitch + column] end
  end
  return table.concat(rows), sum
end

return {
  color_emoji_layout_fits_cells_and_preserves_following_text_columns = function()
    local system = System.new({ pixel_height = 23 })
    local layout, state = Layout.new(system), State.new(20, 1)
    Parser.new(state):feed("😀😀❤️👩‍💻🇸🇬👍🏽X")
    local glyphs = layout:update(state)
    Assert.equal(#glyphs, 7)
    for index = 1, 6 do
      local glyph = glyphs[index]
      Assert.truthy(glyph.cache_entry.bitmap.color)
      Assert.equal(glyph.missing_reason, nil)
      Assert.equal(glyph.cluster_column, (index - 1) * 2)
      Assert.truthy(glyph.x >= glyph.cluster_column and glyph.x + glyph.width <= glyph.cluster_column + 2.001)
      Assert.truthy(glyph.y >= 0 and glyph.y + glyph.height <= 1.001)
      Assert.truthy(require("bit").band(glyph.flags, 0x20000000) ~= 0)
    end
    Assert.equal(glyphs[7].cluster_column, 12)
    Assert.truthy(not glyphs[7].cache_entry.bitmap.color)
    Assert.equal(system.glyph_cache.pixel_bytes, 4 * 1024 * 1024)
    layout:destroy(); system:destroy()
  end,
  fallback_advance_does_not_accumulate_across_terminal_cells = function()
    local system = System.new({ pixel_height = 23 })
    local face = assert(system:face_for_cluster({ 0x4e2d }))
    local shape = face.shape
    face.shape = function(self, text, options)
      local glyphs = shape(self, text, options)
      for _, glyph in ipairs(glyphs) do glyph.x_advance = glyph.x_advance * 3 end
      return glyphs
    end
    local layout, state = Layout.new(system), State.new(8, 1)
    Parser.new(state):feed("中中中")
    local glyphs = layout:update(state)
    Assert.equal(#glyphs, 3)
    Assert.truthy(math.abs(glyphs[2].x - glyphs[1].x - 2) < 1e-6)
    Assert.truthy(math.abs(glyphs[3].x - glyphs[2].x - 2) < 1e-6)
    layout:destroy(); system:destroy()
  end,
  unresolved_fallback_shows_a_placeholder_without_changing_terminal_text = function()
    local system = System.new({ pixel_height = 23, face_cache_limit = 1 })
    local layout, state = Layout.new(system), State.new(4, 1)
    Parser.new(state):feed("中")
    local glyphs = layout:update(state)
    Assert.equal(#glyphs, 1)
    Assert.equal(glyphs[1].glyph_id, system.primary:glyph_index(63))
    Assert.equal(state:get(0, 0).glyph, "中")
    layout:destroy(); system:destroy()
  end,
  emoji_faces_load_at_arbitrary_sizes_and_shape_joiners_and_variation_selectors = function()
    for _, size in ipairs({ 17, 23, 37 }) do
      local system = System.new({ pixel_height = size })
      for _, text in ipairs({ "😀", "❤️", "👩‍💻", "🇸🇬", "👍🏽" }) do
        local codepoints = {}
        local Utf8 = require("kiwi.terminal.utf8")
        local decoder = Utf8.Decoder.new(function(codepoint) codepoints[#codepoints + 1] = codepoint end)
        for index = 1, #text do decoder:feed_byte(text:byte(index)) end
        for _, flags in ipairs({ 0, 1, 16, 17 }) do
          local face = assert(system:face_for_cluster(codepoints, flags), text)
          local shaped = face:shape(text)
          Assert.equal(#shaped, 1, "emoji sequence should shape as one glyph: " .. text)
          local bitmap = face:rasterize(shaped[1].glyph_id)
          Assert.equal(bitmap.pixel_mode, face.native.pixel_mode_bgra)
          Assert.truthy(bitmap.width > 0 and bitmap.height > 0)
          Assert.truthy(shaped[1].x_advance / 64 < size * 3)
          Assert.equal(face.pixel_height, size)
        end
      end
      system:destroy()
    end
  end,
  fallback_retries_a_failed_candidate_without_losing_the_supported_face = function()
    local system = System.new({ pixel_height = 23 })
    local good = system.resolver:fallback({ 0x4e2d })
    system.resolver.fallback = function()
      local bad = { path = "/kiwi/nonexistent/font.ttf", index = 0 }
      return bad, { bad, good }
    end
    local face = assert(system:face_for_cluster({ 0x4e2d }))
    Assert.equal(face.path, good.path)
    Assert.equal(system:face_for_cluster({ 0x4e2d }), face)
    Assert.equal(#system.faces, 2)
    system:destroy()
  end,
  font_styles_choose_real_faces_when_the_family_provides_them = function()
    local family = ffi.os == "OSX" and "Menlo" or "DejaVu Sans Mono"
    local system = System.new({ primary_family = family, pixel_height = 24 })
    local regular = system.primary
    Assert.truthy(not regular.bold and not regular.italic)
    for _, flags in ipairs({ 1, 16, 17 }) do
      local face = assert(system:face_for_cluster({ 65 }, flags))
      Assert.equal(face.family, regular.family)
      Assert.equal(face.bold, flags == 1 or flags == 17)
      Assert.equal(face.italic, flags == 16 or flags == 17)
      Assert.equal(face.synthetic_bold, false)
      Assert.equal(face.synthetic_italic, false)
      Assert.truthy(face.id ~= regular.id)
      Assert.equal(system:face_for_cluster({ 65 }, flags), face)
    end
    Assert.equal(#system.faces, 4)
    system:destroy()
  end,
  font_styles_synthesize_missing_weight_and_slant_in_the_bitmap = function()
    local system = System.new({ pixel_height = 24 })
    local regular = system.primary
    local path = { path = regular.path, index = regular.index }
    local bold = assert(system:load_face(path, false, 1))
    local italic = assert(system:load_face(path, false, 16))
    Assert.equal(bold.synthetic_bold, true)
    Assert.equal(italic.synthetic_italic, true)
    local glyph = regular:glyph_index(string.byte("H"))
    local plain_pixels, plain_coverage = signature(regular:rasterize(glyph))
    local bold_pixels, bold_coverage = signature(bold:rasterize(glyph))
    local italic_pixels = signature(italic:rasterize(glyph))
    Assert.truthy(bold_pixels ~= plain_pixels)
    Assert.truthy(bold_coverage > plain_coverage)
    Assert.truthy(italic_pixels ~= plain_pixels)
    Assert.equal(regular.synthetic_bold, false)
    Assert.equal(regular.synthetic_italic, false)
    Assert.equal(signature(regular:rasterize(glyph)), plain_pixels)
    local first = assert(system.glyph_cache:get_or_insert(regular, glyph))
    local second = assert(system.glyph_cache:get_or_insert(bold, glyph))
    Assert.truthy(first.key ~= second.key)
    system:destroy()
  end,
  font_style_changes_split_shaping_runs_without_changing_terminal_columns = function()
    local system = System.new({ pixel_height = 24 })
    local layout, state = Layout.new(system), State.new(8, 1)
    Parser.new(state):feed("H\27[1mH\27[22;3mH\27[1mH\27[0mH")
    local glyphs = layout:update(state)
    Assert.equal(#glyphs, 5)
    Assert.equal(layout.stats.runs_reshaped, 5)
    for index, glyph in ipairs(glyphs) do
      Assert.equal(glyph.cluster_column, index - 1)
      Assert.equal(state:get(index - 1, 0).width, 1)
    end
    Assert.equal(state.cursor.column, 5)
    Assert.equal(glyphs[1].face_id, glyphs[5].face_id)
    for index = 1, 3 do Assert.truthy(glyphs[index].face_id ~= glyphs[index + 1].face_id) end
    local width, height = system.cell_width, system.cell_height
    layout:update(state)
    Assert.equal(layout.stats.rows_reshaped, 0)
    Assert.equal(system.cell_width, width)
    Assert.equal(system.cell_height, height)
    layout:destroy()
    system:destroy()
  end,
  fallback_font_styles_have_independent_face_and_sequence_caches = function()
    local system = System.new({ pixel_height = 24 })
    local regular = assert(system:face_for_cluster({ 0x4e2d }))
    local bold = assert(system:face_for_cluster({ 0x4e2d }, 1))
    local italic = assert(system:face_for_cluster({ 0x4e2d }, 16))
    Assert.truthy(regular ~= bold and regular ~= italic and bold ~= italic)
    Assert.truthy(bold.bold or bold.synthetic_bold)
    Assert.truthy(italic.italic or italic.synthetic_italic)
    Assert.equal(system:face_for_cluster({ 0x4e2d }, 1), bold)
    Assert.equal(system:face_for_cluster({ 0x4e2d }, 16), italic)
    Assert.equal(system:face_for_cluster({ 0x4e2d }), regular)
    system:destroy()
  end,
  exhausted_font_face_budget_keeps_primary_text_visible_and_bounds_resolution = function()
    local system = System.new({ pixel_height = 18, face_cache_limit = 1 })
    local calls, original = 0, system.resolver.primary
    system.resolver.primary = function(...)
      calls = calls + 1
      return original(...)
    end
    for _ = 1, 20 do Assert.equal(system:face_for_cluster({ 65 }, 17), system.primary) end
    Assert.equal(calls, 1)
    Assert.equal(#system.faces, 1)
    system:destroy()
  end,
}
