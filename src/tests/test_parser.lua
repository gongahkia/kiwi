local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local function run_with_chunks(input, chunks)
  local state = State.new(12, 4)
  local parser = Parser.new(function(action)
    state:apply(action)
  end)
  local offset = 1
  for _, count in ipairs(chunks) do
    if offset > #input then
      break
    end
    parser:feed(input:sub(offset, offset + count - 1))
    offset = offset + count
  end
  if offset <= #input then
    parser:feed(input:sub(offset))
  end
  parser:finish()
  return Snapshot.encode(state), parser.stats, state
end

local function randomized_chunks(length, seed)
  local chunks = {}
  local remaining = length
  while remaining > 0 do
    seed = (seed * 17 + 11) % 97
    local chunk = math.min(remaining, seed % 7 + 1)
    chunks[#chunks + 1] = chunk
    remaining = remaining - chunk
  end
  return chunks
end

return {
  parser_actions_are_chunk_boundary_invariant = function()
    local input = "\27[31mred\27[0m\rX\n\27[2;4H!\27]2;Kiwi\7€"
    local whole = run_with_chunks(input, { #input })
    for split = 1, #input - 1 do
      Assert.equal(run_with_chunks(input, { split, #input - split }), whole, "two-chunk split " .. split)
    end
    local byte_chunks = {}
    for _ = 1, #input do
      byte_chunks[#byte_chunks + 1] = 1
    end
    Assert.equal(run_with_chunks(input, byte_chunks), whole)
    for seed = 1, 16 do
      Assert.equal(run_with_chunks(input, randomized_chunks(#input, seed)), whole, "randomized chunks " .. seed)
    end
  end,
  parser_recovers_from_malformed_and_bounded_strings = function()
    local state = State.new(8, 2)
    local parser = Parser.new(function(action)
      state:apply(action)
    end, { max_string_bytes = 4, max_parameters = 2 })
    parser:feed("\27]2;toolong-title\7ok\27[1;2;3Hstill")
    parser:finish()
    Assert.equal(state:get(0, 0).glyph, "o")
    Assert.truthy(parser.stats.ignored >= 2)
    Assert.truthy(state.stats.unknown.osc >= 1)
  end,
  parser_keeps_syntax_separate_from_state_mutation = function()
    local actions = {}
    local parser = Parser.new(function(action)
      actions[#actions + 1] = action
    end)
    parser:feed("\27[32mA")
    Assert.equal(actions[1].kind, "csi")
    Assert.equal(actions[1].final, "m")
    Assert.equal(actions[2].kind, "print")
    Assert.equal(actions[2].text, "A")
  end,
  parser_state_sink_preserves_terminal_output = function()
    local input = "\27[32mA\27[0m\rB\n€"
    local callback_snapshot = run_with_chunks(input, { #input })
    local state = State.new(12, 4)
    local parser = Parser.new(state)
    parser:feed(input)
    parser:finish()
    Assert.equal(Snapshot.encode(state), callback_snapshot)
  end,
  parser_ascii_sink_matches_callback_across_controls_and_prepend = function()
    local input = "start\27[31m red\27[0m\n" .. string.char(0xd8, 0x80) .. "ABC\rend"
    local callback_snapshot, callback_stats = run_with_chunks(input, { #input })
    local state = State.new(12, 4, { text_counters = {} })
    local parser = Parser.new(state)
    parser:feed(input:sub(1, 7))
    parser:feed(input:sub(8))
    parser:finish()
    Assert.equal(Snapshot.encode(state), callback_snapshot)
    Assert.equal(parser.stats.bytes, #input)
    Assert.equal(parser.stats.actions, callback_stats.actions)
    Assert.truthy(state.text_counters.ascii_fast_path >= 2)
  end,
}
