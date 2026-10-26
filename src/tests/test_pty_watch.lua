local Assert = require("tests.assert")
local Watch = require("kiwi.process.pty_watch")

return {
  readiness_requests_writes_only_while_live_terminal_input_is_pending = function()
    local snapshots, destroyed = {}, 0
    local native = {
      kiwi_pty_watch_update_events = function(_, fds, interests, count)
        local values = {}
        for index = 0, count - 1 do
          values[#values + 1] = { fd = tonumber(fds[index]), interest = tonumber(interests[index]) }
        end
        snapshots[#snapshots + 1] = values
        return 1
      end,
      kiwi_pty_watch_destroy = function() destroyed = destroyed + 1 end,
    }
    local watch = Watch.new(native, function() return {} end)
    local terminal = { fd = 10, pending = "abc", pending_offset = 2 }
    watch:update({ terminal, { fd = 11 }, { fd = 12, eof = true, pending = "x" }, { pending = "closed" } })
    Assert.equal(#snapshots[1], 2)
    Assert.equal(snapshots[1][1].fd, 10)
    Assert.equal(snapshots[1][1].interest, 3)
    Assert.equal(snapshots[1][2].fd, 11)
    Assert.equal(snapshots[1][2].interest, 1)
    terminal.pending_offset = 4
    watch:update({ terminal })
    Assert.equal(snapshots[2][1].interest, 1)
    terminal.pending, terminal.pending_offset = "", 1
    watch:update({ terminal })
    Assert.equal(snapshots[3][1].interest, 1)
    watch:update({})
    Assert.equal(#snapshots[4], 0)
    watch:destroy(); watch:destroy()
    Assert.equal(destroyed, 1)
  end,
  readiness_descriptor_overflow_does_not_replace_the_previous_native_watch = function()
    local calls = 0
    local watch = Watch.new({ kiwi_pty_watch_update_events = function() calls = calls + 1; return 1 end }, function() return {} end)
    local descriptors = {}
    for fd = 1, 65 do descriptors[#descriptors + 1] = { fd = fd } end
    watch:update(descriptors)
    descriptors[66] = { fd = 66 }
    Assert.equal(pcall(watch.update, watch, descriptors), false)
    Assert.equal(calls, 1)
  end,
}
