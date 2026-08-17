local Manager = require("kiwi.app.window_manager")

return {
  live_window_manager_keeps_new_windows_in_one_application_scheduler = function()
    local waits = 0
    local polls = 0
    local created = 0
    local controller_options = {}
    local manager = Manager.new(function(options)
      created = created + 1
      controller_options[created] = options
      local window = { id = created }
      if created == 1 then assert(options.application:request_window()) end
      options.application:await_events(window, 0.001)
    end, { multi_window_smoke = true }, {
      window_api = {
        poll_events_for = function(windows)
          polls = polls + 1
          assert(#windows >= 1)
        end,
        wait_events_for = function(timeout, windows)
          waits = waits + 1
          assert(timeout >= 0)
          assert(#windows >= 1)
        end,
      },
    })
    manager:run()
    assert(created == 2, "new window did not receive a manager-owned controller")
    assert(controller_options[1].multi_window_smoke_requester == true, "the initial controller should own the smoke request")
    assert(controller_options[2].multi_window_smoke_requester == false, "new controllers must not recursively request windows")
    assert(waits == 2 and polls == 2, "each controller turn should share one platform event wait and poll")
    assert(manager:window_count() == 0, "ended controllers must leave the manager")
  end,

  live_window_manager_rejects_recording_and_window_limit_requests = function()
    local recorder_manager = Manager.new(function() end, { record = "recording.jsonl" })
    local opened, reason = recorder_manager:request_window()
    assert(opened == nil and reason == "new windows are unavailable while --record is active")

    local limited_manager = Manager.new(function(options)
      options.application:await_events({}, 0)
    end, { maximum_windows = 1 }, {
      window_api = { poll_events_for = function() end, wait_events_for = function() end },
    })
    assert(limited_manager:request_window())
    local limited, limited_reason = limited_manager:request_window()
    assert(limited == nil and limited_reason == "window-limit")
  end,
}
