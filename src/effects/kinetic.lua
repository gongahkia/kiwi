local Effect = require("effects.effect")

local Kinetic = {}

Kinetic.id = "stanczyk.kinetic"
Kinetic.contract = {
  new = "new(parameters?) -> effect | nil, error",
}

local SCALE = 1000

local function scaled(value)
  return math.floor(value * SCALE + 0.5)
end

local function parameters(effect)
  return effect:parameters()
end

local function clear(state)
  state.bell = 0
  state.output = 0
  state.scroll = 0
  state.scroll_direction = 0
end

local function pulse(state, field, amount)
  state[field] = math.min(SCALE, state[field] + amount)
end

local function decay(value, amount)
  if value == 0 or amount == 0 then
    return value
  end
  return math.max(0, value - math.max(1, amount))
end

function Kinetic.new(overrides)
  local state = { bell = 0, output = 0, scroll = 0, scroll_direction = 0 }
  return Effect.new({
    api_version = 1,
    capabilities = { "terminal_events", "frame_update", "cell_transform", "visual_state" },
    determinism = "deterministic",
    id = Kinetic.id,
    parameters = {
      decay = { default = 0.6, max = 1, min = 0.05, type = "number" },
      intensity = { default = 0.35, max = 1, min = 0, type = "number" },
      max_offset = { default = 0.25, max = 0.5, min = 0.01, type = "number" },
      reduced_motion = { default = false, type = "boolean" },
    },
    version = "0.1.0",
  }, {
    needs_redraw = function(effect)
      local values = parameters(effect)
      return not values.reduced_motion
        and values.intensity > 0
        and (state.bell > 0 or state.output > 0 or state.scroll > 0)
    end,
    on_event = function(effect, _, event)
      local values = parameters(effect)
      if values.reduced_motion then
        clear(state)
        return true
      end
      if event.kind == "output" then
        local length = math.min(#event.payload.bytes, 32)
        pulse(state, "output", math.max(1, math.floor(length * scaled(values.intensity) / 32)))
      elseif event.kind == "bell" then
        pulse(state, "bell", math.max(1, scaled(values.intensity)))
      elseif event.kind == "scroll" then
        pulse(state, "scroll", math.max(1, event.payload.count * scaled(values.intensity)))
        state.scroll_direction = event.payload.direction == "up" and -1 or 1
      elseif
        event.kind == "checkpoint_restored"
        or event.kind == "replay_reset"
        or event.kind == "replay_seek"
      then
        clear(state)
      end
      return true
    end,
    transform_cell = function(effect, _, cell)
      local values = parameters(effect)
      if values.reduced_motion or values.intensity == 0 then
        return nil
      end
      local energy = state.output + state.bell + state.scroll
      if energy == 0 then
        return nil
      end
      local direction = (cell.row + cell.column) % 2 == 0 and 1 or -1
      local maximum = values.max_offset * values.intensity
      local output = state.output / SCALE
      local bell = state.bell / SCALE
      local scroll = state.scroll / SCALE
      return {
        offset_x = direction * maximum * (output + bell * 0.5),
        offset_y = state.scroll_direction * maximum * scroll + direction * maximum * bell * 0.25,
      }
    end,
    update = function(effect, _, delta_us)
      local values = parameters(effect)
      if values.reduced_motion then
        clear(state)
        return true
      end
      local amount = math.floor(delta_us * scaled(values.decay) / 1000000)
      state.bell = decay(state.bell, amount)
      state.output = decay(state.output, amount)
      state.scroll = decay(state.scroll, amount)
      if state.scroll == 0 then
        state.scroll_direction = 0
      end
      return true
    end,
  }, overrides)
end

return Kinetic
