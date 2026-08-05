local assertions = require("support.assertions")
local Effect = require("effects.effect")
local Host = require("effects.host")
local Terminal = require("terminal.terminal")

local function manifest()
  return {
    api_version = 1,
    capabilities = { "cell_observation", "frame_update", "terminal_events" },
    determinism = "deterministic",
    id = "test.generated",
    parameters = {},
    version = "0.1.0",
  }
end

return {
  {
    name = "property generated effect lifecycle sequences preserve runtime invariants",
    run = function()
      local terminal = assert(Terminal.new({ columns = 4, rows = 2 }))
      assert(terminal:feed_output("AB"))
      local digest = assert(terminal:digest())
      local previous_event_sequence = 0
      local previous_timestamp = 0
      local effect = assert(Effect.new(manifest(), {
        on_cell = function(_, _, cell)
          assertions.truthy(cell.row >= 1)
          assertions.truthy(cell.column >= 1)
        end,
        on_event = function(_, _, event)
          assertions.truthy(event.sequence > previous_event_sequence)
          assertions.truthy(event.timestamp_us >= previous_timestamp)
          previous_event_sequence = event.sequence
          previous_timestamp = event.timestamp_us
        end,
        update = function(_, _, delta_us)
          assertions.truthy(delta_us >= 0)
        end,
      }))
      local host = assert(Host.new({ effect }, {
        terminal = { columns = 4, rows = 2 },
        viewport = { height = 32, width = 64 },
      }))
      for _ = 1, 128 do
        local action = math.random(1, 4)
        if action == 1 then
          assert(host:update(math.random(0, 100)))
        elseif action == 2 then
          assert(
            host:emit(
              "output",
              { bytes = string.char(math.random(65, 90)) },
              host:status().elapsed_us
            )
          )
        elseif action == 3 then
          assert(
            host:resize(
              { height = math.random(16, 64), width = math.random(16, 128) },
              { columns = math.random(1, 12), rows = math.random(1, 6) },
              host:status().elapsed_us
            )
          )
        else
          local backing = terminal.primary_screen.rows[1].cells[1]
          assert(host:observe_cells({
            {
              attributes = backing.attributes,
              background = backing.background,
              column = 1,
              cursor = false,
              damage = true,
              foreground = backing.foreground,
              row = 1,
              screen = "primary",
              text = backing.text,
              width = backing.width,
            },
          }, math.random(0, 1) == 1))
        end
      end
      assertions.equal(digest, assert(terminal:digest()))
      assertions.equal(previous_event_sequence, host:status().event_sequence)
    end,
  },
}
