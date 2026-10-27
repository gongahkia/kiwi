local Assert = require("tests.assert")
local Atspi = require("kiwi.accessibility.atspi")
local State = require("kiwi.terminal.state")

return {
  atspi_projection_avoids_an_iterator_allocation_for_each_ascii_cell = function()
    local state = State.new(120, 44)
    state:write_codepoint("A")
    state:write_codepoint("界")
    state:write_codepoint("e")
    state:write_codepoint("́", 0x301)
    local projector = Atspi.new()
    local function project(count)
      local value
      for _ = 1, count do value = projector:project(state) end
      return value
    end
    project(50)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local ok, value = xpcall(function() return project(100) end, debug.traceback)
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    assert(ok, value)
    -- Previously ~47 MiB of transient data for 100 otherwise unchanged views.
    Assert.truthy(allocated < 16 * 1024, "AT-SPI projection allocated " .. allocated .. " KiB")
    Assert.equal(value.text:sub(1, #"A界é"), "A界é")
    Assert.equal(value.character_count, 120 * 44 + 43)
    Assert.equal(value.caret_offset, 4)
  end,
  atspi_projection_exports_a_bounded_utf8_viewport_with_semantic_offsets = function()
    local state = State.new(4, 2)
    state:write_codepoint("A")
    state:write_codepoint("界")
    state:write_codepoint("B")
    state:set_cursor(0, 1)
    state:write_codepoint("C")
    state:set_cursor(2, 0)
    local projection = Atspi.new():project(state)
    Assert.equal(projection.text, "A界B\nC   ")
    Assert.equal(projection.character_count, 8)
    Assert.equal(projection.caret_offset, 2)
    Assert.equal(projection.selection_start, -1)
    Assert.equal(projection.selection_end, -1)
  end,
  atspi_projection_keeps_the_export_within_its_utf8_budget = function()
    local state = State.new(4, 1)
    state:write_codepoint("界")
    state:write_codepoint("界")
    local projection = Atspi.new({ max_rows = 1, max_bytes = 5 }):project(state)
    Assert.equal(projection.text, "界")
    Assert.equal(projection.character_count, 1)
    Assert.truthy(projection.truncated)
  end,
}
