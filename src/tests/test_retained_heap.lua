local Assert = require("tests.assert")
local RetainedHeap = require("kiwi.bench.retained_heap")

return {
  retained_heap_measures_live_roots_and_discards_temporary_garbage = function()
    local now = 0
    local recording = RetainedHeap.new(function() now = now + 1; return now end)
    local retained = {}
    recording:capture("initial")
    for index = 1, 10000 do retained[index] = { index, index + 1, index + 2, index + 3 } end
    recording:capture("final")
    local grown = recording:observations()
    Assert.truthy(grown.growth_kib > 512, "retained allocations were not observed")
    local stable = RetainedHeap.new(function() now = now + 1; return now end)
    stable:capture("initial")
    for _ = 1, 3 do
      local temporary = {}
      for index = 1, 10000 do temporary[index] = { index, index + 1, index + 2, index + 3 } end
    end
    stable:capture("final")
    Assert.truthy(stable:observations().growth_kib < 128, "temporary allocations were retained")
    Assert.equal(retained[10000][1], 10000) -- Keep the deliberately retained root live.
  end,
  retained_heap_keeps_bounded_independent_checkpoints_and_collection_cost = function()
    local now, counts, calls = 0, { 500, 100, 900, 120 }, {}
    local recording = RetainedHeap.new(function() now = now + 0.25; return now end, function(operation)
      calls[#calls + 1] = operation
      if operation == "count" then return table.remove(counts, 1) end
    end)
    local history = { limit = 2, retained = 2, pushed = 4, evicted = 2 }
    recording:capture("initial", history)
    history.pushed, history.evicted = 8, 6
    Assert.equal(recording:observations().initial.history.pushed, 4)
    Assert.equal(recording:observations().growth_kib, nil)
    recording:capture("final", history)
    local snapshot = recording:observations()
    Assert.equal(snapshot.growth_kib, 20)
    Assert.equal(snapshot.duration_seconds, 0.25)
    Assert.equal(snapshot.initial.collection_seconds, 0.25)
    Assert.equal(snapshot.final.history.evicted, 6)
    Assert.equal(table.concat(calls, ","), "count,collect,count,count,collect,count")
    snapshot.initial.history.retained = 0
    snapshot.initial.after_kib = 999
    Assert.equal(recording:observations().initial.after_kib, 100)
    Assert.equal(recording:observations().initial.history.retained, 2)
    Assert.equal(pcall(recording.capture, recording, "initial", history), false)
    Assert.equal(pcall(recording.capture, recording, "final", history), false)
    Assert.equal(#calls, 6)
  end,
  retained_heap_rejects_incomplete_history_and_invalid_order_before_collecting = function()
    local calls = 0
    local recording = RetainedHeap.new(function() return 0 end, function() calls = calls + 1; return 0 end)
    Assert.equal(pcall(recording.capture, recording, "final"), false)
    Assert.equal(pcall(recording.capture, recording, "unknown"), false)
    Assert.equal(pcall(recording.capture, recording, "initial", { limit = 2, retained = 1, pushed = 1, evicted = 0 }), false)
    Assert.equal(pcall(recording.capture, recording, "initial", { limit = 2, retained = 2, pushed = 1, evicted = 0 }), false)
    Assert.equal(calls, 0)
    Assert.equal(recording:observations().initial, nil)
  end,
  retained_heap_preserves_initial_evidence_when_final_collection_fails = function()
    local fail, now = false, 0
    local recording = RetainedHeap.new(function() now = now + 1; return now end, function(operation)
      if fail and operation == "collect" then error("collection failed") end
      return 10
    end)
    recording:capture("initial")
    fail = true
    Assert.equal(pcall(recording.capture, recording, "final"), false)
    Assert.equal(recording:observations().initial.after_kib, 10)
    Assert.equal(recording:observations().final, nil)
    Assert.equal(recording:observations().growth_kib, nil)
  end,
}
