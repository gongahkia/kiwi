local Extensions = require("kiwi.renderer.extensions")
local PassRegistry = require("kiwi.renderer.pass_registry")
local Resources = require("kiwi.renderer.resources")

local Soak = {}

local function core_pass(name, order, events, after)
  return {
    name = name,
    order = order,
    reads = {},
    writes = {},
    after = after or {},
    initialize = function() events[#events + 1] = name .. ":initialize" end,
    encode = function() events[#events + 1] = name .. ":encode" end,
    resize = function() events[#events + 1] = name .. ":resize" end,
    shutdown = function() events[#events + 1] = name .. ":shutdown" end,
  }
end

local function renderer_stub()
  return {
    frame_time = 0,
    resolve_pass_resources = function() return {} end,
    schedule_animation = function() return 0 end,
    schedule_extension_animation = function() return 0 end,
  }
end

function Soak.run(options)
  options = options or {}
  local cycles = options.cycles or 32
  assert(type(cycles) == "number" and cycles >= 1 and cycles % 1 == 0, "device soak cycles must be a positive integer")
  local result = {
    cycles = cycles,
    extension_disables = 0,
    lifecycle = { minimize = 0, resize = 0, restore = 0 },
    native_releases = 0,
  }
  for cycle = 1, cycles do
    local events = {}
    local builtins = {
      core_pass("terminal/background", 10, events),
      core_pass("terminal/glyph", 20, events, { "terminal/background" }),
      core_pass("terminal/cursor", 30, events, { "terminal/glyph" }),
    }
    local extensions = Extensions.new({ diagnostic_limit = 2 })
    local optional = extensions:register({ function(api)
      api:register({
        after = { "terminal/glyph" },
        api_version = 1,
        encode = function()
          if cycle % 2 == 0 then error("soak optional pass failure") end
        end,
        extension = "soak",
        name = "toggle",
        order = 25,
        reads = {},
        writes = {},
      })
    end }, builtins)
    local registry = PassRegistry.new({
      on_optional_failure = function(pass, phase, message)
        extensions:disable_pass(pass, phase, message)
      end,
    })
    for _, pass in ipairs(builtins) do registry:register(pass) end
    for _, pass in ipairs(optional) do registry:register(pass) end
    local resources = Resources.new(cycle)
    local first, second = {}, {}
    resources:own_native("soak-first", first, function() result.native_releases = result.native_releases + 1 end)
    resources:own_native("soak-second", second, function() result.native_releases = result.native_releases + 1 end)

    local renderer = renderer_stub()
    registry:initialize(renderer)
    registry:resize(renderer, { columns = 80, rows = 24 }, { columns = 79, rows = 24 })
    result.lifecycle.resize = result.lifecycle.resize + 1
    result.lifecycle.minimize = result.lifecycle.minimize + 1
    result.lifecycle.restore = result.lifecycle.restore + 1
    registry:encode(renderer, nil, nil, {})
    local activity = registry:activity_snapshot()
    assert(activity.active == nil, "device soak found a stale active pass")
    if cycle % 2 == 0 then
      assert(extensions:snapshot().disabled["extension/soak/toggle"], "device soak optional failure was not disabled")
      result.extension_disables = result.extension_disables + 1
    end
    registry:shutdown(renderer)
    assert(registry.state == "destroyed" and #registry.initialized == 0, "device soak found an uncleared pass lifecycle")
    resources:destroy()
    assert(resources.destroyed and next(resources.owned) == nil and next(resources.owned_handles) == nil, "device soak found a stale owned resource")
  end
  assert(result.native_releases == cycles * 2, "device soak found an unreleased owned resource")
  return result
end

local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(window, options)
  options = options or {}
  local seconds = options.seconds or 10
  local interval = options.interval or 0.25
  assert(type(seconds) == "number" and seconds > 0, "device soak duration must be positive")
  assert(type(interval) == "number" and interval > 0, "device soak interval must be positive")
  return setmetatable({
    duration_seconds = seconds,
    interval = interval,
    minimized = false,
    next_step = 0,
    started = nil,
    stats = { minimize = 0, resize = 0, restore = 0 },
    window = window,
  }, Lifecycle)
end

function Lifecycle:step(now)
  if self.started == nil then self.started = now end
  local elapsed = now - self.started
  if elapsed >= self.duration_seconds then
    if self.minimized then
      self.window:restore()
      self.minimized = false
      self.stats.restore = self.stats.restore + 1
    end
    return true
  end
  local step = math.floor(elapsed / self.interval)
  if step < self.next_step then return false end
  self.next_step = step + 1
  local phase = step % 3
  if phase == 0 then
    local width = step % 6 == 0 and 1440 or 1600
    self.window:set_size(width, 900)
    self.stats.resize = self.stats.resize + 1
  elseif phase == 1 then
    self.window:iconify()
    self.minimized = true
    self.stats.minimize = self.stats.minimize + 1
  else
    self.window:restore()
    self.minimized = false
    self.stats.restore = self.stats.restore + 1
  end
  return false
end

function Lifecycle:snapshot()
  return {
    duration_seconds = self.duration_seconds,
    interval_seconds = self.interval,
    lifecycle = { minimize = self.stats.minimize, resize = self.stats.resize, restore = self.stats.restore },
  }
end

Soak.Lifecycle = Lifecycle

function Soak.main()
  local value = tonumber(os.getenv("KIWI_DEVICE_SOAK_CYCLES"))
  local result = Soak.run({ cycles = value and math.floor(value) or 32 })
  io.stdout:write(string.format(
    "device soak cycles=%d resize=%d minimize=%d restore=%d extension-disables=%d native-releases=%d\n",
    result.cycles,
    result.lifecycle.resize,
    result.lifecycle.minimize,
    result.lifecycle.restore,
    result.extension_disables,
    result.native_releases
  ))
end

if ... == nil then Soak.main() end

return Soak
