local Assert = require("tests.assert")
local Schedule = require("kiwi.app.poll_schedule")

return {
  scheduling_services_output_backlogs_and_expired_frames_without_an_idle_wait = function()
    Assert.equal(Schedule.timeout(1, nil, true, false), 0)
    Assert.equal(Schedule.timeout(1, nil, true, true), 0)
    Assert.equal(Schedule.timeout(1, 0.99, false, false), 0)
    Assert.equal(Schedule.timeout(1, 1, false, false), 0)
    Assert.near(Schedule.timeout(1, 1.016, false, false), 0.016, 1e-10)
  end,
  scheduling_does_not_spin_when_no_render_deadline_or_output_is_pending = function()
    Assert.equal(Schedule.timeout(1, nil, false, false), math.huge)
    Assert.equal(Schedule.timeout(1, nil, false, true), math.huge)
    Assert.equal(Schedule.timeout(1, 2, false, false), 1)
    Assert.equal(Schedule.timeout(1, 2, false, true), 1)
  end,
  scheduling_uses_timed_reaping_only_for_live_children_without_exit_notifications = function()
    Assert.equal(Schedule.child_timeout({}, false), math.huge)
    Assert.equal(Schedule.child_timeout({ { fd = 3 }, { pid = 4, exit_fd = 5 } }, false), math.huge)
    Assert.equal(Schedule.child_timeout({ { pid = 4, exited = true } }, false), math.huge)
    Assert.equal(Schedule.child_timeout({ { pid = 4, eof = true } }, false), 0.050)
    Assert.equal(Schedule.child_timeout({ { pid = 4, eof = true } }, true), 0.250)
  end,
}
