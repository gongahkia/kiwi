local assertions = require("support.assertions")
local Effect = require("effects.effect")
local Host = require("effects.host")

local function manifest()
  return {
    api_version = 1,
    capabilities = { "cell_observation", "deterministic_random", "frame_update", "terminal_events" },
    determinism = "deterministic",
    id = "test.generated-random",
    parameters = {},
    version = "0.1.0",
  }
end

local function cell()
  return {
    attributes = 0,
    background = "default",
    column = 1,
    cursor = false,
    damage = true,
    foreground = "default",
    row = 1,
    screen = "primary",
    text = "A",
    width = 1,
  }
end

local function trace(seed, actions)
  local values = {}
  local effect = assert(Effect.new(manifest(), {
    on_cell = function(_, context)
      values[#values + 1] = "c" .. context.random:integer(0, 9)
    end,
    on_event = function(_, context)
      values[#values + 1] = "e" .. context.random:next_u32()
    end,
    update = function(_, context)
      values[#values + 1] = "u" .. context.random:integer(-100, 100)
    end,
  }))
  local host = assert(Host.new({ effect }, { random_seed = seed }))
  for _, action in ipairs(actions) do
    if action.kind == "update" then
      assert(host:update(action.delta_us))
    elseif action.kind == "event" then
      assert(host:emit("output", { bytes = action.bytes }, host:status().elapsed_us))
    else
      assert(host:observe_cells({ cell() }, action.full_redraw))
    end
  end
  return table.concat(values, ":")
end

return {
  {
    name = "property generated lifecycle calls reproduce seeded random streams",
    run = function()
      local actions = {}
      for _ = 1, 128 do
        local kind = math.random(1, 3)
        if kind == 1 then
          actions[#actions + 1] = { delta_us = math.random(0, 100), kind = "update" }
        elseif kind == 2 then
          actions[#actions + 1] = {
            bytes = string.char(math.random(65, 90)),
            kind = "event",
          }
        else
          actions[#actions + 1] = { full_redraw = math.random(0, 1) == 1, kind = "cell" }
        end
      end
      local first = trace(1234, actions)
      local second = trace(1234, actions)
      local changed = trace(4321, actions)
      assertions.equal(first, second)
      assertions.falsy(first == changed)
      assertions.truthy(#first > 0)
    end,
  },
}
