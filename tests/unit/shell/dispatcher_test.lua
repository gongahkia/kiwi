local assertions = require("support.assertions")
local Dispatcher = require("shell.dispatcher")
local Registry = require("shell.registry")
local Errors = require("runtime.errors")

return {
  {
    name = "sandbox dispatcher tokenizes before lookup and treats zero argv as a no-op",
    run = function()
      local lookups = 0
      local registry = {
        command = function()
          lookups = lookups + 1
          return {
            name = "status",
            run = function() end,
          }
        end,
      }
      local dispatcher = assert(Dispatcher.new(registry))
      local outcome = assert(dispatcher:dispatch(" \t "))
      assertions.falsy(outcome.dispatched)
      assertions.equal(0, lookups)
      for _, input in ipairs({ "status 'unterminated", 'status "unterminated', "status\\" }) do
        local dispatched, token_error = dispatcher:dispatch(input)
        assertions.falsy(dispatched)
        assertions.equal("sandbox_command_error", token_error.kind)
        assertions.equal(0, lookups)
      end
      local bounded = assert(Dispatcher.new(registry, { limits = { max_arguments = 1 } }))
      local dispatched, token_error = bounded:dispatch("status extra")
      assertions.falsy(dispatched)
      assertions.equal("too_many_arguments", token_error.detail.reason)
      assertions.equal(0, lookups)
    end,
  },
  {
    name = "sandbox dispatcher supplies exact isolated argv and private output after successful tokenization",
    run = function()
      local registry = assert(Registry.new())
      local received
      assert(registry:register("show", {
        capabilities = { "domain_events" },
        run = function(_, argv, writer)
          received = { argv[1], argv[2], argv[3] }
          argv[2] = "changed"
          assert(writer:emit("result\0"))
          return 7
        end,
        summary = "Show opaque bytes",
      }))
      local dispatcher = assert(Dispatcher.new(registry))
      local outcome = assert(dispatcher:dispatch('show "a b" ' .. string.char(0, 255)))
      assertions.truthy(outcome.dispatched)
      assertions.equal("show", outcome.command)
      assertions.equal("show", received[1])
      assertions.equal("a b", received[2])
      assertions.equal(string.char(0, 255), received[3])
      assertions.equal("a b", outcome.argv[2])
      assertions.equal(7, outcome.result)
      assertions.falsy(outcome.failed)
      assertions.equal("finished_with_output", outcome.invocation:status().state)
      local output = assert(outcome.invocation:poll())
      assertions.equal("result\0", output.events[1].data)
      assertions.equal(0, output.events[1].delta_us)
    end,
  },
  {
    name = "sandbox dispatch preserves registry copy isolation after tokenization",
    run = function()
      local registry = assert(Registry.new())
      local definition = {
        capabilities = { "domain_events" },
        run = function() end,
        summary = "Original summary",
      }
      assert(registry:register("status", definition))
      definition.capabilities[1] = "vfs.write"
      definition.summary = "mutated"
      local dispatcher = assert(Dispatcher.new(registry))
      assert(dispatcher:dispatch('status "quoted argument"'))
      local command = assert(registry:command("status"))
      assertions.equal("Original summary", command.summary)
      assertions.equal("domain_events", command.capabilities[1])
    end,
  },
  {
    name = "sandbox dispatcher retains private output when a command callback fails",
    run = function()
      local registry = assert(Registry.new())
      assert(registry:register("fail", {
        run = function(_, _, writer)
          assert(writer:emit("before failure"))
          error("failure")
        end,
        summary = "Fail deliberately",
      }))
      local dispatcher = assert(Dispatcher.new(registry))
      local outcome = assert(dispatcher:dispatch("fail"))
      assertions.truthy(outcome.failed)
      assertions.equal("sandbox_command_error", outcome.failure.kind)
      assertions.equal("command_failed", outcome.failure.detail.reason)
      assertions.equal("failed_with_output", outcome.invocation:status().state)
      assertions.equal("before failure", assert(outcome.invocation:poll()).events[1].data)
      assertions.truthy(outcome.invocation:status().settled)
      assertions.truthy(registry:command("fail"))
    end,
  },
  {
    name = "sandbox dispatcher reports overflow while preserving output and stable poll sequence",
    run = function()
      local registry = assert(Registry.new())
      assert(registry:register("overflow", {
        run = function(_, _, writer)
          assert(writer:emit("keep"))
          local emitted, output_error = writer:emit("drop")
          assertions.falsy(emitted)
          assertions.equal("output_overflow", output_error.detail.reason)
        end,
        summary = "Overflow output",
      }))
      local dispatcher = assert(Dispatcher.new(registry, {
        output_limits = {
          max_drain_bytes = 4,
          max_output_events = 1,
          max_queued_bytes = 4,
          max_queued_chunks = 1,
          max_write_bytes = 4,
        },
      }))
      local outcome = assert(dispatcher:dispatch("overflow"))
      assertions.truthy(outcome.failed)
      assertions.equal("output_overflow", outcome.failure.detail.reason)
      local event = assert(outcome.invocation:poll()).events[1]
      assertions.equal("keep", event.data)
      assertions.equal(1, event.source_sequence)
      local second = assert(dispatcher:dispatch("overflow"))
      local second_event = assert(second.invocation:poll()).events[1]
      assertions.equal(2, second_event.source_sequence)
    end,
  },
  {
    name = "sandbox dispatcher retains typed callback failures without replacing their causes",
    run = function()
      local registry = assert(Registry.new())
      assert(registry:register("typed", {
        run = function()
          local error_value = Errors.new("sandbox_command_error", "typed failure", {
            reason = "typed_failure",
          })
          return nil, error_value
        end,
        summary = "Return a typed failure",
      }))
      local outcome = assert(Dispatcher.new(registry)):dispatch("typed")
      assertions.truthy(outcome.failed)
      assertions.equal("typed_failure", outcome.failure.detail.reason)
    end,
  },
}
