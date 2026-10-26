local Assert = require("tests.assert")
local Runtime = require("kiwi.app.configuration_runtime")

local function fixture(callback)
  local path = os.tmpname()
  local function save(text)
    local file = assert(io.open(path, "wb")); file:write(text); file:close()
  end
  save("font-size = 16\ntheme = kiwi\n")
  local watch = { fd = 19, changed = false, reads = 0 }
  function watch:take_changes()
    self.reads = self.reads + 1
    local changed = self.changed; self.changed = false; return changed
  end
  local window = { watch_files = function(_, paths) watch.paths = paths; return watch end }
  local runtime = Runtime.new(window, {}, { config = path })
  local ok, reason = xpcall(function() callback(runtime, watch, save) end, debug.traceback)
  os.remove(path)
  assert(ok, reason)
end

return {
  configuration_runtime_debounces_changes_and_does_not_retry_rejected_edits = function()
    fixture(function(runtime, watch, save)
      local initial, calls = runtime.configuration, 0
      local function apply() calls = calls + 1; return true end
      local descriptors = {}; runtime:append_watch(descriptors)
      Assert.equal(descriptors[1], watch)
      save("font-size = 999\n"); watch.changed = true
      Assert.equal(runtime:poll(1, apply), false)
      Assert.near(runtime:timeout(1, math.huge), 0.2, 1e-9)
      Assert.equal(runtime:poll(1.1, apply), false)
      Assert.equal(runtime:poll(1.21, apply), false)
      Assert.equal(calls, 0)
      Assert.equal(runtime.configuration, initial)
      Assert.truthy(runtime.status.error)
      Assert.equal(runtime:timeout(2, math.huge), math.huge)
      runtime:poll(3, apply)
      Assert.equal(calls, 0)
      save("font-size = 18\n"); watch.changed = true
      runtime:poll(4, apply)
      Assert.equal(runtime:poll(4.21, apply), true)
      Assert.equal(calls, 1)
      Assert.equal(runtime.configuration.font_size, 18)
      Assert.equal(runtime.status.error, nil)
    end)
  end,
  configuration_runtime_manual_reload_survives_opt_out_and_apply_failure = function()
    fixture(function(runtime, watch, save)
      save("font-size = 18\nlive-config-reload = false\n")
      runtime:request()
      Assert.equal(runtime:timeout(0, math.huge), 0)
      Assert.truthy(runtime:poll(0, function() return true end))
      local accepted, reads = runtime.configuration, watch.reads
      save("font-size = 20\n"); watch.changed = true
      local descriptors = {}; runtime:append_watch(descriptors)
      Assert.equal(#descriptors, 0)
      Assert.equal(runtime:poll(1, function() error("must not apply automatically") end), false)
      Assert.equal(watch.reads, reads)
      runtime:request()
      Assert.equal(runtime:poll(2, function() return nil, "injected resource failure" end), false)
      Assert.equal(runtime.configuration, accepted)
      Assert.truthy(runtime.status:title("terminal"):find("injected resource failure", 1, true))
      runtime:request()
      Assert.truthy(runtime:poll(3, function() return true end))
      Assert.equal(runtime.configuration.font_size, 20)
      Assert.equal(runtime.configuration.live_config_reload, true)
      Assert.equal(runtime.status.error, nil)
    end)
  end,
  configuration_runtime_keeps_failed_dependencies_and_reports_watcher_failure = function()
    fixture(function(runtime, watch, save)
      local missing = os.tmpname(); os.remove(missing)
      save("theme-file = " .. missing .. "\n")
      runtime:request()
      Assert.equal(runtime:poll(0, function() error("invalid source must not apply") end), false)
      local found = false
      for _, path in ipairs(watch.paths) do if path == missing then found = true end end
      Assert.truthy(found)
      watch.take_changes = function() error("injected watcher failure") end
      Assert.equal(runtime:poll(1, function() return true end), false)
      Assert.equal(runtime.watch, nil)
      Assert.truthy(runtime.status.error:find("injected watcher failure", 1, true))
    end)
  end,
}
