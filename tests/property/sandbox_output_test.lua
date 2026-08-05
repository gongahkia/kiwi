local assertions = require("support.assertions")
local Output = require("shell.output")

local limits = {
  max_drain_bytes = 8,
  max_output_events = 4,
  max_queued_bytes = 24,
  max_queued_chunks = 4,
  max_write_bytes = 8,
}

local byte_choices = { "a", "Z", " ", "\0", "\255", "\\" }

local function bytes(length)
  local result = {}
  for index = 1, length do
    result[index] = byte_choices[math.random(1, #byte_choices)]
  end
  return table.concat(result)
end

local function queue_bytes(chunks)
  return #table.concat(chunks)
end

local function drain(chunks, maximum)
  local result = {}
  local remaining = maximum
  while remaining > 0 and #chunks > 0 do
    local head = chunks[1]
    local take = math.min(#head, remaining)
    result[#result + 1] = head:sub(1, take)
    remaining = remaining - take
    if take == #head then
      table.remove(chunks, 1)
    else
      chunks[1] = head:sub(take + 1)
    end
  end
  return table.concat(result)
end

return {
  {
    name = "property generated sandbox output emit and poll sequences conserve bounded FIFO bytes",
    run = function()
      for iteration = 1, 128 do
        local invocation = assert(Output.new(limits))
        local writer = invocation:writer()
        local expected = {}
        local emitted = {}
        local observed = {}
        local closed = false
        for _ = 1, 64 do
          if not closed and math.random(1, 3) ~= 1 then
            local value = bytes(math.random(0, 10))
            local accepted, emit_error = writer:emit(value)
            if #value == 0 then
              assertions.truthy(accepted)
            elseif #value > limits.max_write_bytes then
              assertions.falsy(accepted)
              assertions.equal("emit_too_large", emit_error.detail.reason)
              closed = true
            elseif
              queue_bytes(expected) + #value > limits.max_queued_bytes
              or #expected >= limits.max_queued_chunks
            then
              assertions.falsy(accepted)
              assertions.equal("output_overflow", emit_error.detail.reason)
              closed = true
            else
              assertions.truthy(accepted)
              expected[#expected + 1] = value
              emitted[#emitted + 1] = value
            end
          else
            local maximum = math.random(1, limits.max_drain_bytes)
            local result = assert(invocation:poll({ max_bytes = maximum, max_events = 1 }))
            local actual = result.events[1] and result.events[1].data or ""
            assertions.equal(drain(expected, maximum), actual, "poll iteration " .. iteration)
            observed[#observed + 1] = actual
          end
          local status = invocation:status()
          assertions.truthy(status.queued_bytes <= limits.max_queued_bytes)
          assertions.truthy(status.queued_chunks <= limits.max_queued_chunks)
        end
        assert(invocation:complete())
        while invocation:status().queued_chunks > 0 do
          local result = assert(invocation:poll())
          observed[#observed + 1] = result.events[1].data
        end
        assertions.equal(
          table.concat(emitted),
          table.concat(observed),
          "bytes iteration " .. iteration
        )
      end
    end,
  },
  {
    name = "property generated sandbox output poll sizes preserve concatenated accepted bytes",
    run = function()
      for iteration = 1, 128 do
        local values = {}
        local total_bytes = 0
        for index = 1, math.random(1, 3) do
          local maximum = math.min(limits.max_write_bytes, limits.max_queued_bytes - total_bytes)
          values[index] = bytes(math.random(1, maximum))
          total_bytes = total_bytes + #values[index]
        end
        local left = assert(Output.new(limits))
        local right = assert(Output.new(limits))
        for _, value in ipairs(values) do
          assert(left:writer():emit(value))
          assert(right:writer():emit(value))
        end
        local left_output = {}
        local right_output = {}
        while left:status().queued_chunks > 0 do
          left_output[#left_output + 1] =
            assert(left:poll({ max_bytes = 1, max_events = 1 })).events[1].data
        end
        while right:status().queued_chunks > 0 do
          right_output[#right_output + 1] =
            assert(right:poll({ max_bytes = 8, max_events = 1 })).events[1].data
        end
        assertions.equal(
          table.concat(values),
          table.concat(left_output),
          "left iteration " .. iteration
        )
        assertions.equal(
          table.concat(values),
          table.concat(right_output),
          "right iteration " .. iteration
        )
      end
    end,
  },
}
