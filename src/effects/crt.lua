local Effect = require("effects.effect")

local CRT = {}

CRT.id = "stanczyk.crt"
CRT.contract = {
  new = "new(parameters?) -> effect | nil, error",
}

local SCALE = 1000
local MAX_SCANLINES = 256

local function scaled(value)
  return math.floor(value * SCALE + 0.5)
end

local function parameters(effect)
  return effect:parameters()
end

local function pulse(state, amount)
  state.phosphor = math.min(SCALE, state.phosphor + amount)
end

local function scanline_colour(values)
  local intensity = scaled(values.intensity)
  return {
    alpha = 0.04 + intensity * 0.00018,
    blue = 0.01,
    green = 0.025,
    red = 0.005,
  }
end

local function bloom_colour(values, phosphor)
  local bloom = scaled(values.bloom)
  local alpha = math.floor(bloom * phosphor / SCALE) * 0.00016
  return {
    alpha = alpha,
    blue = 0.1,
    green = 0.72,
    red = 0.2,
  }
end

function CRT.new(overrides)
  local state = { phosphor = 0 }
  return Effect.new({
    api_version = 1,
    capabilities = { "terminal_events", "canvas_after", "frame_update" },
    determinism = "deterministic",
    id = CRT.id,
    parameters = {
      bloom = { default = 0.2, max = 0.5, min = 0, type = "number" },
      intensity = { default = 0.35, max = 1, min = 0, type = "number" },
      persistence = { default = 0.2, max = 1, min = 0, type = "number" },
      reduced_motion = { default = false, type = "boolean" },
      scanline_spacing = { default = 3, max = 8, min = 2, type = "integer" },
    },
    version = "0.1.0",
  }, {
    after_canvas = function(effect, _, canvas)
      local values = parameters(effect)
      if values.intensity == 0 then
        return true
      end
      local spacing = math.max(values.scanline_spacing, math.ceil(canvas.height / MAX_SCANLINES))
      local colour = scanline_colour(values)
      for y = spacing - 1, canvas.height - 1, spacing do
        local drawn, draw_error = canvas:fill_rect(0, y, canvas.width, 1, colour)
        if not drawn then
          return nil, draw_error
        end
      end
      if not values.reduced_motion and state.phosphor > 0 and values.bloom > 0 then
        local glow = bloom_colour(values, state.phosphor)
        if glow.alpha > 0 then
          local drawn, draw_error = canvas:fill_rect(0, 0, canvas.width, canvas.height, glow)
          if not drawn then
            return nil, draw_error
          end
        end
      end
      return true
    end,
    on_event = function(effect, _, event)
      local values = parameters(effect)
      if event.kind == "output" then
        pulse(state, math.max(1, scaled(values.intensity)))
      elseif event.kind == "bell" then
        pulse(state, math.max(1, scaled(values.intensity) * 2))
      elseif
        event.kind == "checkpoint_restored"
        or event.kind == "replay_reset"
        or event.kind == "replay_seek"
      then
        state.phosphor = 0
      end
      return true
    end,
    update = function(effect, _, delta_us)
      local values = parameters(effect)
      if values.reduced_motion or values.persistence == 0 then
        state.phosphor = 0
        return true
      end
      local retention = scaled(values.persistence)
      local decay = math.floor(delta_us * (SCALE - retention) / 1000000)
      state.phosphor = math.max(0, state.phosphor - decay)
      return true
    end,
  }, overrides)
end

return CRT
