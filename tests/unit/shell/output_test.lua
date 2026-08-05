local assertions = require("support.assertions")
local Output = require("shell.output")

local function emit_error(writer, bytes, reason)
  local emitted, error_value = writer:emit(bytes)
  assertions.falsy(emitted)
  assertions.equal("sandbox_command_error", error_value.kind)
  assertions.equal(reason, error_value.detail.reason)
end

local function poll(invocation, limits)
  local result, poll_error = invocation:poll(limits)
  assertions.falsy(poll_error)
  return result
end

local function event_bytes(result)
  local chunks = {}
  for index, event in ipairs(result.events) do
    chunks[index] = event.data
  end
  return table.concat(chunks)
end

return {
  {
    name = "sandbox output polls an empty private queue without events",
    run = function()
      local invocation = assert(Output.new())
      local result = poll(invocation)
      assertions.equal(0, #result.events)
      assertions.equal("running", result.status.execution_state)
      assertions.equal(0, result.status.queued_bytes)
      assertions.equal(0, result.status.queued_chunks)
    end,
  },
  {
    name = "sandbox output rejects disabled limits and exhausted event resources before queue mutation",
    run = function()
      local invocation, limit_error = Output.new({ max_queued_bytes = 0 })
      assertions.falsy(invocation)
      assertions.equal("sandbox_command_error", limit_error.kind)
      invocation, limit_error = Output.new({ max_queued_chunks = -1 })
      assertions.falsy(invocation)
      assertions.equal("sandbox_command_error", limit_error.kind)

      invocation = assert(Output.new(nil, function()
        return nil
      end))
      assert(invocation:writer():emit("queued"))
      local result, resource_error = invocation:poll()
      assertions.falsy(result)
      assertions.equal("output_resource_limit", resource_error.detail.reason)
      assertions.equal(6, invocation:status().queued_bytes)
    end,
  },
  {
    name = "sandbox output preserves FIFO opaque bytes and zero-length no-ops",
    run = function()
      local invocation = assert(Output.new())
      local writer = invocation:writer()
      local source = "first"
      assert(writer:emit(source))
      source = "changed"
      assert(writer:emit(""))
      assert(writer:emit("\0\255second"))
      local result = poll(invocation)
      assertions.equal("first\0\255second", event_bytes(result))
      assertions.equal(1, #result.events)
      assertions.equal(0, result.events[1].delta_us)
      assertions.equal(1, result.events[1].source_sequence)
      assertions.equal(0, result.status.queued_bytes)
      assertions.truthy(invocation:complete())
      assertions.truthy(invocation:status().settled)
    end,
  },
  {
    name = "sandbox output validates immutable write and queue bounds atomically",
    run = function()
      local invocation = assert(Output.new({
        max_drain_bytes = 4,
        max_output_events = 1,
        max_queued_bytes = 5,
        max_queued_chunks = 2,
        max_write_bytes = 3,
      }))
      local writer = invocation:writer()
      assert(writer:emit("abc"))
      emit_error(writer, "abcd", "emit_too_large")
      assertions.truthy(invocation:status().failed)
      assertions.equal("output_overflow", invocation:status().failure.detail.reason)
      emit_error(writer, "de", "output_closed")
      assertions.equal("abc", event_bytes(poll(invocation)))

      invocation = assert(Output.new({
        max_drain_bytes = 4,
        max_output_events = 1,
        max_queued_bytes = 5,
        max_queued_chunks = 2,
        max_write_bytes = 3,
      }))
      writer = invocation:writer()
      assert(writer:emit("abc"))
      assert(writer:emit("de"))
      local status = invocation:status()
      assertions.equal(5, status.queued_bytes)
      assertions.equal(2, status.queued_chunks)
      emit_error(writer, "x", "output_overflow")
      status = invocation:status()
      assertions.truthy(status.failed)
      assertions.equal("output_overflow", status.failure.detail.reason)
      assertions.equal(5, status.queued_bytes)
      assertions.equal(2, status.queued_chunks)
      emit_error(writer, "z", "output_closed")
      assert(invocation:complete())
      assertions.equal("failed_with_output", invocation:status().state)
      assertions.equal("abcd", event_bytes(poll(invocation)))
      assertions.equal("e", event_bytes(poll(invocation)))
      assertions.truthy(invocation:status().settled)
      assertions.equal("failed", invocation:status().state)
      assertions.equal("output_overflow", invocation:status().failure.detail.reason)
    end,
  },
  {
    name = "sandbox output rejects chunk overflow while preserving earlier queued bytes",
    run = function()
      local invocation = assert(Output.new({
        max_drain_bytes = 5,
        max_output_events = 1,
        max_queued_bytes = 5,
        max_queued_chunks = 1,
        max_write_bytes = 5,
      }))
      local writer = invocation:writer()
      assert(writer:emit("a"))
      emit_error(writer, "b", "output_overflow")
      assertions.equal("a", event_bytes(poll(invocation)))
      assert(invocation:complete())
      assertions.truthy(invocation:status().settled)
    end,
  },
  {
    name = "sandbox output splits queue heads deterministically and validates poll limits before draining",
    run = function()
      local invocation = assert(Output.new({
        max_drain_bytes = 3,
        max_output_events = 1,
        max_queued_bytes = 8,
        max_queued_chunks = 2,
        max_write_bytes = 5,
      }))
      local writer = invocation:writer()
      assert(writer:emit("abcde"))
      assert(writer:emit("f"))
      local invalid, invalid_error = invocation:poll({ max_bytes = 0 })
      assertions.falsy(invalid)
      assertions.equal("invalid_poll_limit", invalid_error.detail.reason)
      assertions.equal(6, invocation:status().queued_bytes)
      invalid, invalid_error = invocation:poll({ max_events = 2 })
      assertions.falsy(invalid)
      assertions.equal("invalid_poll_limit", invalid_error.detail.reason)
      assertions.equal(6, invocation:status().queued_bytes)
      local first = poll(invocation, { max_bytes = 3, max_events = 1 })
      assertions.equal("abc", event_bytes(first))
      assertions.equal(3, invocation:status().queued_bytes)
      local second = poll(invocation, { max_bytes = 3, max_events = 1 })
      assertions.equal("def", event_bytes(second))
      assertions.equal(1, first.events[1].source_sequence)
      assertions.equal(2, second.events[1].source_sequence)
      assertions.equal(0, second.events[1].delta_us)
      assertions.equal(0, invocation:status().queued_chunks)
    end,
  },
  {
    name = "sandbox output distinguishes finished failed cancelled and released queue states",
    run = function()
      local finished = assert(Output.new())
      assert(finished:writer():emit("kept"))
      assert(finished:complete())
      assertions.equal("finished_with_output", finished:status().state)
      emit_error(finished:writer(), "closed", "output_closed")
      assertions.equal("kept", event_bytes(poll(finished)))
      assertions.equal("settled", finished:status().state)
      assertions.truthy(finished:release())
      assertions.truthy(finished:release())
      assertions.truthy(finished:status().released)

      local cancelled = assert(Output.new())
      assert(cancelled:writer():emit("preserved"))
      assert(cancelled:cancel())
      assertions.equal("cancelled", cancelled:status().execution_state)
      assertions.equal("cancelled", cancelled:status().failure.detail.reason)
      emit_error(cancelled:writer(), "closed", "output_closed")
      assertions.equal("preserved", event_bytes(poll(cancelled)))
      assertions.truthy(cancelled:status().settled)
      assertions.truthy(cancelled:release())
    end,
  },
}
