local Assert = require("tests.assert")
local GpuTiming = require("kiwi.renderer.gpu_timing")

local function context(status)
  return { timestamp_status = function() return status end }
end

local function passes()
  return {
    { name = "terminal/background", pipeline = true },
    { name = "extension/example/semantic" },
    { name = "terminal/glyph", pipeline = true },
  }
end

return {
  gpu_timing_reports_the_explicit_unsupported_path_without_allocating = function()
    local created = false
    local timing = GpuTiming.new(context({ requested = true, supported = false, enabled = false, reason = "adapter does not expose timestamp-query" }), passes(), {
      backend = { create = function() created = true end },
    })
    local snapshot = timing:snapshot()
    Assert.equal(created, false)
    Assert.equal(snapshot.enabled, false)
    Assert.equal(snapshot.status, "adapter does not expose timestamp-query")
    Assert.equal(#snapshot.samples, 0)
  end,
  gpu_timing_attributes_delayed_samples_and_bounds_history_without_waiting = function()
    local events = {}
    local polls = {
      {},
      {
        { frame = 1, pass_index = 1, begin_ticks = 30, end_ticks = 47, map_latency_ms = 2.5 },
        { frame = 1, pass_index = 0, begin_ticks = 10, end_ticks = 20, map_latency_ms = 2.5 },
      },
    }
    local backend = {
      create = function(count)
        Assert.equal(count, 2)
        return {}
      end,
      begin = function(_, frame)
        events[#events + 1] = "begin-" .. frame
        return true
      end,
      writes = function(_, index)
        return "writes-" .. index
      end,
      resolve = function() events[#events + 1] = "resolve" end,
      submit = function() events[#events + 1] = "submit" end,
      poll = function()
        events[#events + 1] = "poll"
        return table.remove(polls, 1)
      end,
      pending = function() return 1 end,
      dropped = function() return 2 end,
      destroy = function() events[#events + 1] = "destroy" end,
    }
    local timing = GpuTiming.new(context({ requested = true, supported = true, enabled = true, reason = "enabled" }), passes(), { backend = backend, history_limit = 1 })
    Assert.equal(timing:begin_frame(), true)
    Assert.equal(timing:writes("terminal/background"), "writes-0")
    Assert.equal(timing:writes("terminal/glyph"), "writes-1")
    Assert.equal(timing:writes("extension/example/semantic"), nil)
    timing:resolve({})
    timing:submit()
    timing:poll()
    timing:poll()
    local snapshot = timing:snapshot()
    Assert.equal(snapshot.status, "supported")
    Assert.equal(snapshot.pending, 1)
    Assert.equal(snapshot.dropped, 2)
    Assert.equal(#snapshot.history, 1)
    Assert.equal(snapshot.samples[1].name, "terminal/background")
    Assert.equal(snapshot.samples[1].gpu_ticks, 10)
    Assert.equal(snapshot.samples[2].name, "terminal/glyph")
    Assert.equal(snapshot.samples[2].gpu_ticks, 17)
    timing:destroy()
    Assert.equal(table.concat(events, ","), "begin-1,resolve,submit,poll,poll,destroy")
  end,
}
