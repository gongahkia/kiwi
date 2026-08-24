local Assert = require("tests.assert")
local Attributes = require("kiwi.terminal.attributes")
local Corpus = require("tests.fixtures.vt")
local Parser = require("kiwi.terminal.parser")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local function chunks_for_randomized_boundaries(length, seed)
  local chunks = {}
  local remaining = length
  while remaining > 0 do
    seed = (seed * 17 + 11) % 97
    local count = math.min(remaining, seed % 7 + 1)
    chunks[#chunks + 1] = count
    remaining = remaining - count
  end
  return chunks
end

local function run(fixture, chunks)
  local state_options = { scrollback_limit = 16 }
  for name, value in pairs(fixture.state_options or {}) do state_options[name] = value end
  local state = State.new(fixture.columns, fixture.rows, state_options)
  local parser = Parser.new(function(action)
    state:apply(action)
  end, fixture.parser_options)
  local offset = 1
  for _, count in ipairs(chunks) do
    if offset > #fixture.input then
      break
    end
    parser:feed(fixture.input:sub(offset, offset + count - 1))
    offset = offset + count
  end
  if offset <= #fixture.input then
    parser:feed(fixture.input:sub(offset))
  end
  parser:finish()
  return state, parser, Snapshot.encode(state)
end

local function row_text(state, row)
  local text = {}
  for column = 0, state.columns - 1 do
    text[#text + 1] = state:get(column, row).glyph
  end
  return table.concat(text)
end

local function assert_sequence(actual, expected, label)
  Assert.equal(#actual, #expected, label .. " count")
  for index, value in ipairs(expected) do
    Assert.equal(actual[index], value, label .. " item " .. index)
  end
end

local function assert_expected(fixture, state, parser)
  local expected = fixture.expected
  for row, text in ipairs(expected.rows or {}) do
    Assert.equal(row_text(state, row - 1), text, fixture.id .. " row " .. row)
  end
  if expected.cursor then
    Assert.equal(state.cursor.column, expected.cursor.column, fixture.id .. " cursor column")
    Assert.equal(state.cursor.row, expected.cursor.row, fixture.id .. " cursor row")
    if expected.cursor.pending_wrap ~= nil then
      Assert.equal(state.cursor.pending_wrap, expected.cursor.pending_wrap, fixture.id .. " pending wrap")
    end
  end
  if expected.active_screen then
    Assert.equal(state.active_screen == state.primary and "primary" or "alternate", expected.active_screen, fixture.id .. " active screen")
  end
  if expected.margins then
    Assert.equal(state.active_screen.top_margin, expected.margins.top, fixture.id .. " top margin")
    Assert.equal(state.active_screen.bottom_margin, expected.margins.bottom, fixture.id .. " bottom margin")
    if expected.margins.left ~= nil then
      Assert.equal(state.active_screen.left_margin, expected.margins.left, fixture.id .. " left margin")
    end
    if expected.margins.right ~= nil then
      Assert.equal(state.active_screen.right_margin, expected.margins.right, fixture.id .. " right margin")
    end
  end
  if expected.modes then
    for name, value in pairs(expected.modes) do
      Assert.equal(state.modes[name], value, fixture.id .. " mode " .. name)
    end
  end
  if expected.scrollback_lines then
    Assert.equal(state.scrollback:size(), expected.scrollback_lines, fixture.id .. " scrollback")
  end
  if expected.title then
    Assert.equal(state.title, expected.title, fixture.id .. " title")
  end
  if expected.pointer_shape then
    Assert.equal(state.pointer_shape, expected.pointer_shape, fixture.id .. " pointer shape")
  end
  if expected.unknown then
    for family, count in pairs(expected.unknown) do
      Assert.equal(state.stats.unknown[family], count, fixture.id .. " unknown " .. family)
    end
  end
  if expected.parser then
    for name, value in pairs(expected.parser) do
      Assert.equal(parser.stats[name], value, fixture.id .. " parser " .. name)
    end
  end
  if expected.shell then
    local shell = state.shell:view()
    if expected.shell.current_directory then
      Assert.equal(shell.current_directory and shell.current_directory.uri, expected.shell.current_directory, fixture.id .. " current directory")
    end
    if expected.shell.events then
      Assert.equal(#shell.events, #expected.shell.events, fixture.id .. " shell event count")
      for index, kind in ipairs(expected.shell.events) do Assert.equal(shell.events[index].kind, kind, fixture.id .. " shell event " .. index) end
    end
  end
  if expected.command_regions then
    local regions = state.command_regions:view()
    Assert.equal(#regions.regions, 1, fixture.id .. " command-region count")
    for name, value in pairs(expected.command_regions) do
      Assert.equal(regions.regions[1][name], value, fixture.id .. " command-region " .. name)
    end
  end
  if expected.kitty_placements then
    local placements = state:kitty_placements_view().placements
    local count = expected.kitty_placements.count or 1
    Assert.equal(#placements, count, fixture.id .. " kitty placement count")
    for name, value in pairs(expected.kitty_placements) do
      if name ~= "count" then Assert.equal(placements[1][name], value, fixture.id .. " kitty placement " .. name) end
    end
  end
  if expected.kitty_graphics then
    local graphics = state.kitty_graphics:view()
    for name, value in pairs(expected.kitty_graphics) do
      if name == "image_id" then
        Assert.equal(graphics.images[1] and graphics.images[1].id, value, fixture.id .. " kitty image id")
      elseif name == "last_error" then
        Assert.equal(graphics.stats.last_error, value, fixture.id .. " kitty graphics error")
      else
        Assert.equal(graphics[name], value, fixture.id .. " kitty graphics " .. name)
      end
    end
  end
  if expected.responses then
    assert_sequence(state:pop_responses(), expected.responses, fixture.id .. " responses")
  end
  for _, cell_expected in ipairs(expected.cells or {}) do
    local cell = state:get(cell_expected.column, cell_expected.row)
    if cell_expected.flags ~= nil then
      Assert.equal(cell.flags, cell_expected.flags, fixture.id .. " cell flags")
    end
    if cell_expected.default_fg then
      Assert.equal(cell.fg, Attributes.default_foreground, fixture.id .. " default foreground")
    end
    if cell_expected.fg then
      local foreground = Attributes.resolve({ fg = cell_expected.fg })
      Assert.equal(cell.fg, foreground, fixture.id .. " cell foreground")
    end
    if cell_expected.hyperlink_uri then
      Assert.truthy(cell.hyperlink_id ~= nil, fixture.id .. " hyperlink identity")
      Assert.equal(state.hyperlinks[cell.hyperlink_id].uri, cell_expected.hyperlink_uri, fixture.id .. " hyperlink URI")
    elseif cell_expected.no_hyperlink then
      Assert.equal(cell.hyperlink_id, nil, fixture.id .. " no hyperlink")
    end
  end
end

return {
  conformance_corpus_matches_declared_terminal_semantics = function()
    for _, fixture in ipairs(Corpus) do
      local state, parser = run(fixture, { #fixture.input })
      assert_expected(fixture, state, parser)
    end
  end,
  conformance_corpus_is_chunk_boundary_invariant = function()
    for _, fixture in ipairs(Corpus) do
      local _, _, whole = run(fixture, { #fixture.input })
      for split = 1, #fixture.input - 1 do
        local _, _, split_snapshot = run(fixture, { split, #fixture.input - split })
        Assert.equal(split_snapshot, whole, fixture.id .. " split " .. split)
      end
      local one_byte = {}
      for _ = 1, #fixture.input do
        one_byte[#one_byte + 1] = 1
      end
      local _, _, one_byte_snapshot = run(fixture, one_byte)
      Assert.equal(one_byte_snapshot, whole, fixture.id .. " one-byte chunks")
      for seed = 1, 8 do
        local _, _, randomized_snapshot = run(fixture, chunks_for_randomized_boundaries(#fixture.input, seed))
        Assert.equal(randomized_snapshot, whole, fixture.id .. " randomized chunks " .. seed)
      end
    end
  end,
}
