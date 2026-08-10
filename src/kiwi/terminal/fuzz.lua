local Parser = require("kiwi.terminal.parser")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local Fuzz = {}

local default_parser_options = {
  max_parameters = 8,
  max_parameter_value = 1000,
  max_intermediates = 2,
  max_string_bytes = 64,
}

local modulus = 2147483647

local function copy_options(options)
  local copy = {}
  for name, value in pairs(default_parser_options) do copy[name] = value end
  for name, value in pairs(options or {}) do copy[name] = value end
  return copy
end

local function fail(message)
  error("terminal fuzz invariant: " .. message, 3)
end

local function assert_invariant(condition, message)
  if not condition then fail(message) end
end

local function random(seed)
  seed = math.floor(tonumber(seed) or 1) % (modulus - 1) + 1
  return function(limit)
    seed = (seed * 48271) % modulus
    return seed % limit
  end
end

local function hexadecimal(bytes)
  return (bytes:gsub(".", function(byte) return string.format("%02x", byte:byte()) end))
end

function Fuzz.decode_hexadecimal(value)
  assert(type(value) == "string" and #value % 2 == 0 and value:match("^[0-9a-fA-F]*$") ~= nil, "fuzz replay input must be even-length hexadecimal")
  return (value:gsub("%x%x", function(pair) return string.char(tonumber(pair, 16)) end))
end

local function chunks_for(length, seed)
  local next_value = random(seed)
  local chunks = {}
  local remaining = length
  while remaining > 0 do
    local count = math.min(remaining, next_value(11) + 1)
    chunks[#chunks + 1] = count
    remaining = remaining - count
  end
  return chunks
end

local fragments = {
  "\27[31m",
  "\27[0m",
  "\27[?1049h",
  "\27[?1049l",
  "\27[?2004h",
  "\27[?2004l",
  "\27[1;2H",
  "\27[1:2m",
  "\27]2;fuzz\7",
  "\27]2;broken\27x",
  "\27Pdiscard\27\\",
  "\27^discard\27\\",
  "\27_discard\27\\",
  "\27Xdiscard\27\\",
  "\195",
  "\226\130",
  string.char(0x90),
  string.char(0x9b),
  string.char(0x9d),
}

local function generated_input(seed, maximum_bytes)
  local next_value = random(seed)
  local chunks = {}
  local size = 0
  while size < maximum_bytes do
    local piece
    if next_value(4) == 0 then
      piece = fragments[next_value(#fragments) + 1]
    else
      piece = string.char(next_value(256))
    end
    if size + #piece > maximum_bytes then piece = piece:sub(1, maximum_bytes - size) end
    chunks[#chunks + 1] = piece
    size = size + #piece
  end
  return table.concat(chunks)
end

local function assert_damage(damage, count, label)
  assert_invariant(damage.count == count, label .. " damage count")
  assert_invariant(damage.dirty_count >= 0 and damage.dirty_count <= count, label .. " dirty count")
  local previous_last = -1
  local covered = 0
  for _, range in ipairs(damage:ranges()) do
    assert_invariant(range.first >= 0 and range.count >= 0 and range.first + range.count <= count, label .. " damage range bounds")
    assert_invariant(range.first > previous_last, label .. " damage ranges overlap")
    previous_last = range.first + range.count - 1
    covered = covered + range.count
  end
  assert_invariant(covered == damage.dirty_count, label .. " damage coverage")
end

local function assert_screen(state, screen, label)
  assert_invariant(screen.columns == state.columns and screen.rows_count == state.rows, label .. " dimensions")
  assert_invariant(screen.top_margin >= 0 and screen.top_margin < state.rows, label .. " top margin")
  assert_invariant(screen.bottom_margin >= screen.top_margin and screen.bottom_margin < state.rows, label .. " bottom margin")
  assert_invariant(screen.cursor.column >= 0 and screen.cursor.column < state.columns, label .. " cursor column")
  assert_invariant(screen.cursor.row >= 0 and screen.cursor.row < state.rows, label .. " cursor row")
  for row_index = 0, state.rows - 1 do
    local row = screen.rows[row_index]
    assert_invariant(row ~= nil, label .. " missing row " .. row_index)
    for column = 0, state.columns - 1 do
      local cell = row.cells[column]
      assert_invariant(cell ~= nil and type(cell.glyph) == "string", label .. " missing cell " .. row_index .. ":" .. column)
      if cell.continuation then
        local anchor = column > 0 and row.cells[column - 1] or nil
        assert_invariant(cell.width == 0 and cell.anchor_column == column - 1, label .. " continuation metadata")
        assert_invariant(anchor ~= nil and not anchor.continuation and anchor.width == 2, label .. " continuation anchor")
      else
        assert_invariant(cell.width == 1 or cell.width == 2, label .. " anchor width")
        if cell.width == 2 then
          local continuation = column + 1 < state.columns and row.cells[column + 1] or nil
          assert_invariant(continuation ~= nil and continuation.continuation and continuation.anchor_column == column, label .. " wide continuation")
        end
        if cell.codepoints then
          assert_invariant(#cell.codepoints <= state.max_cluster_codepoints, label .. " cluster bound")
        end
      end
    end
  end
end

local function assert_state(state, parser, input, parser_options)
  assert_invariant(parser.mode == "ground", "parser finish mode")
  assert_invariant(parser.stats.bytes == #input, "parser byte progress")
  assert_invariant(parser.stats.actions >= 0 and parser.stats.actions <= #input * 2 + 1, "parser action bound")
  assert_invariant(parser.stats.errors >= 0 and parser.stats.ignored >= 0, "parser statistic bounds")
  assert_invariant(parser.string_size == nil or parser.string_size <= parser_options.max_string_bytes, "control-string bound")
  assert_invariant(parser.string_chunks == nil or #parser.string_chunks <= parser_options.max_string_bytes, "control-string chunk bound")
  assert_invariant(parser.parameters == nil or #parser.parameters <= parser_options.max_parameters, "CSI parameter bound")
  assert_invariant(parser.intermediates == nil or #parser.intermediates <= parser_options.max_intermediates, "CSI intermediate bound")
  assert_invariant(parser.escape_intermediates == nil or #parser.escape_intermediates <= parser_options.max_intermediates, "ESC intermediate bound")
  assert_invariant(parser.current_parameter == nil or parser.current_parameter <= parser_options.max_parameter_value, "CSI parameter value bound")
  assert_invariant(state.active_screen == state.primary or state.active_screen == state.alternate, "active screen identity")
  assert_invariant(state.cursor == state.active_screen.cursor, "active cursor identity")
  assert_invariant(state.scrollback:size() <= state.scrollback.limit, "scrollback bound")
  assert_invariant(state.history_offset >= 0 and state.history_offset <= state.scrollback:size(), "history offset")
  assert_invariant(#state.stats.unknown_samples <= 16, "unknown sample bound")
  if state.title then assert_invariant(#state.title <= parser_options.max_string_bytes, "title bound") end
  assert_screen(state, state.primary, "primary")
  assert_screen(state, state.alternate, "alternate")
  assert_damage(state.damage, state.columns * state.rows, "logical")
  assert_damage(state.text_damage, state.columns * state.rows, "text")
end

local function stats_value(stats)
  return { actions = stats.actions, bytes = stats.bytes, errors = stats.errors, ignored = stats.ignored }
end

local function same_stats(left, right)
  return left.actions == right.actions and left.bytes == right.bytes and left.errors == right.errors and left.ignored == right.ignored
end

local function run_input(input, chunks, parser_options)
  local state = State.new(8, 4, { scrollback_limit = 8, max_cluster_codepoints = 8 })
  local parser = Parser.new(state, parser_options)
  local offset = 1
  for _, count in ipairs(chunks) do
    if offset > #input then break end
    parser:feed(input:sub(offset, offset + count - 1))
    offset = offset + count
  end
  if offset <= #input then parser:feed(input:sub(offset)) end
  parser:finish()
  assert_state(state, parser, input, parser_options)
  return Snapshot.encode(state), stats_value(parser.stats)
end

local function verify_input(input, seed, parser_options)
  local whole_snapshot, whole_stats = run_input(input, { #input }, parser_options)
  local split_snapshot, split_stats = run_input(input, chunks_for(#input, seed), parser_options)
  assert_invariant(split_snapshot == whole_snapshot, "chunk-boundary snapshot seed=" .. seed)
  assert_invariant(same_stats(split_stats, whole_stats), "chunk-boundary stats seed=" .. seed)
end

function Fuzz.minimize(input, predicate)
  local reduced = input
  local granularity = 2
  while #reduced > 0 do
    local chunk_size = math.max(1, math.ceil(#reduced / granularity))
    local changed = false
    for first = 1, #reduced, chunk_size do
      local candidate = reduced:sub(1, first - 1) .. reduced:sub(first + chunk_size)
      if predicate(candidate) then
        reduced = candidate
        granularity = 2
        changed = true
        break
      end
    end
    if not changed then
      if granularity >= #reduced then break end
      granularity = math.min(#reduced, granularity * 2)
    end
  end
  return reduced
end

local function verify_with_repro(input, seed, parser_options, label)
  local ok, message = xpcall(function() verify_input(input, seed, parser_options) end, debug.traceback)
  if ok then return end
  local minimized = Fuzz.minimize(input, function(candidate)
    return not pcall(verify_input, candidate, seed, parser_options)
  end)
  error(string.format("terminal fuzz failure label=%s seed=%d input_hex=%s replay=KIWI_FUZZ_SEED=%d KIWI_FUZZ_REPLAY_HEX=%s: %s", label, seed, hexadecimal(minimized), seed, hexadecimal(minimized), message), 0)
end

function Fuzz.run(options)
  options = options or {}
  local seed = options.seed or 0x4b495749
  local cases = options.cases == nil and 128 or options.cases
  local maximum_bytes = options.maximum_bytes or 512
  assert(type(cases) == "number" and cases >= 0 and cases % 1 == 0, "fuzz case count must be a non-negative integer")
  assert(type(maximum_bytes) == "number" and maximum_bytes >= 1 and maximum_bytes % 1 == 0, "fuzz maximum bytes must be a positive integer")
  local parser_options = copy_options(options.parser_options)
  local corpus_count = 0
  if options.include_corpus ~= false then
    for _, fixture in ipairs(require("tests.fixtures.fuzz")) do
      local fixture_options = copy_options(fixture.parser_options)
      verify_with_repro(fixture.input, seed, fixture_options, fixture.id)
      corpus_count = corpus_count + 1
    end
  end
  if options.input ~= nil then
    verify_with_repro(options.input, seed, parser_options, "replay")
    return { cases = 1, corpus = corpus_count, maximum_bytes = #options.input, seed = seed }
  end
  local next_value = random(seed)
  for index = 1, cases do
    local case_seed = next_value(modulus - 1) + 1
    verify_with_repro(generated_input(case_seed, maximum_bytes), case_seed, parser_options, "generated-" .. index)
  end
  return { cases = cases, corpus = corpus_count, maximum_bytes = maximum_bytes, seed = seed }
end

return Fuzz
