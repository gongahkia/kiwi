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
    for fd = 1, 64 do descriptors[#descriptors + 1] = { fd = fd, exit_fd = fd + 64 } end
    descriptors[65] = { fd = 129 }
    watch:update(descriptors)
    descriptors[66] = { fd = 130 }
    Assert.equal(pcall(watch.update, watch, descriptors), false)
    Assert.equal(calls, 1)
  end,
  readiness_keeps_exit_notifications_after_terminal_eof_and_removes_reaped_children = function()
    local snapshot
    local watch = Watch.new({ kiwi_pty_watch_update_events = function(_, fds, interests, count)
      snapshot = {}
      for i = 0, count - 1 do snapshot[#snapshot + 1] = { tonumber(fds[i]), tonumber(interests[i]) } end
      return 1
    end }, function() return {} end)
    local child = { fd = 10, exit_fd = 11, eof = true }
    watch:update({ child })
    Assert.equal(#snapshot, 1)
    Assert.equal(snapshot[1][1], 11)
    Assert.equal(snapshot[1][2], 1)
    child.exited = true
    watch:update({ child })
    Assert.equal(#snapshot, 0)
    watch:update({ { fd = 12, exit_fd = 13, pending = "x" } })
    Assert.equal(#snapshot, 2)
    Assert.equal(snapshot[1][2], 3)
    Assert.equal(snapshot[2][1], 13)
    Assert.equal(snapshot[2][2], 1)
  end,
}
