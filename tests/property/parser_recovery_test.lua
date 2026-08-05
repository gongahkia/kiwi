local assertions = require("support.assertions")
local Parser = require("terminal.parser")

local malformed_streams = {
  { bytes = "\27[\127m", config = {} },
  { bytes = "\27\127F", config = {} },
  { bytes = "\27[12\24", config = {} },
  { bytes = "\27[1234m", config = { max_csi_bytes = 3 } },
  { bytes = "\27]abc\7", config = { max_osc_bytes = 2 } },
  { bytes = "\27  !F", config = { max_escape_intermediate_bytes = 1 } },
}

local valid_fragments = {
  "A",
  "\7",
  "\n",
  "é",
  "\27[2J",
  "\27[31m",
  "\27[0m",
  "\27]0;title\7",
  "\27" .. "7",
  "\27" .. "8",
}

local function event_signature(event)
  return table.concat({
    event.kind or "",
    event.byte or "",
    event.final or "",
    event.intermediates or "",
    event.parameters or "",
    event.payload or "",
    event.terminator or "",
    event.reason or "",
    event.state or "",
    event.state_before or "",
    event.state_after or "",
  }, ":")
end

local function events_signature(events)
  local signatures = {}
  for index, event in ipairs(events) do
    signatures[index] = event_signature(event)
  end
  return table.concat(signatures, "\n")
end

local function generated_valid_stream()
  local stream = {}
  for index = 1, math.random(1, 16) do
    stream[index] = valid_fragments[math.random(1, #valid_fragments)]
  end
  return table.concat(stream) .. "Z"
end

local function feed_in_chunks(parser, bytes)
  local events = {}
  local offset = 1
  while offset <= #bytes do
    local size = math.random(1, math.min(5, #bytes - offset + 1))
    local chunk_events = assert(parser:feed(bytes:sub(offset, offset + size - 1)))
    for _, event in ipairs(chunk_events) do
      events[#events + 1] = event
    end
    offset = offset + size
  end
  return events
end

local function assert_recovery_state(parser, context)
  local state = parser:snapshot()
  assertions.equal("ground", state.state, context .. " state")
  assertions.equal("", state.csi_intermediates, context .. " CSI intermediates")
  assertions.equal("", state.csi_parameters, context .. " CSI parameters")
  assertions.equal("", state.escape_intermediates, context .. " ESC intermediates")
  assertions.equal("", state.osc_payload, context .. " OSC payload")
end

return {
  {
    name = "property parser recovers from generated malformed input",
    run = function()
      for iteration = 1, 128 do
        local malformed = malformed_streams[math.random(1, #malformed_streams)]
        local recovered = assert(Parser.new(malformed.config))
        local malformed_events = feed_in_chunks(recovered, malformed.bytes)
        local saw_malformed = false
        for _, event in ipairs(malformed_events) do
          saw_malformed = saw_malformed or event.kind == "malformed"
        end
        assertions.truthy(saw_malformed, "malformed property iteration " .. iteration)
        assert_recovery_state(recovered, "malformed property iteration " .. iteration)

        local valid = generated_valid_stream()
        local recovered_events = feed_in_chunks(recovered, valid)
        local clean = assert(Parser.new(malformed.config))
        local clean_events = assert(clean:feed(valid))
        assertions.equal(
          events_signature(clean_events),
          events_signature(recovered_events),
          "recovery event property iteration " .. iteration
        )
        assert_recovery_state(recovered, "recovery property iteration " .. iteration)
        assert_recovery_state(clean, "clean property iteration " .. iteration)
      end
    end,
  },
}
