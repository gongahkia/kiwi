local Assert = require("tests.assert")
local Effects = require("kiwi.app.host_effects")

local function configuration(notification, progress)
  return { osc9_notifications = notification or "off", osc9_progress = progress or "off" }
end

return {
  host_effects_default_deny_is_explicit_and_payload_free = function()
    local effects = Effects.new(configuration(), {}, {})
    local handled, status, first = effects:consume({ kind = "notification_requested", value = { body = "build complete" } })
    Assert.truthy(handled)
    Assert.equal(status, "disabled")
    Assert.truthy(first)
    local snapshot = effects:snapshot()
    Assert.equal(snapshot.diagnostics[1].kind, "notification")
    Assert.equal(snapshot.diagnostics[1].status, "disabled")
    Assert.equal(snapshot.diagnostics[1].body, nil)
  end,
  host_effects_submit_only_configured_valid_requests = function()
    local notifications = {}
    local progress = {}
    local host = {
      notify = function(window, title, body)
        notifications[#notifications + 1] = { body = body, title = title, window = window }
        return true
      end,
      set_progress = function(window, value, state)
        progress[#progress + 1] = { state = state, value = value, window = window }
        return true
      end,
    }
    local window = {}
    local effects = Effects.new(configuration("system", "system"), host, window)
    local handled, status = effects:consume({ kind = "notification_requested", value = { body = "build complete" } })
    Assert.truthy(handled)
    Assert.equal(status, "submitted")
    Assert.equal(notifications[1].title, "Kiwi terminal")
    Assert.equal(notifications[1].body, "build complete")
    Assert.equal(notifications[1].window, window)
    handled, status = effects:consume({ kind = "progress_changed", value = { progress = 73, state = 1 } })
    Assert.truthy(handled)
    Assert.equal(status, "submitted")
    Assert.equal(progress[1].value, 73)
    Assert.equal(progress[1].state, 1)
    Assert.equal(progress[1].window, window)
    handled, status = effects:consume({ kind = "progress_changed", value = { state = 3 } })
    Assert.truthy(handled)
    Assert.equal(status, "submitted")
    Assert.equal(progress[2].value, 73)
    Assert.equal(progress[2].state, 3)
  end,
  host_effects_retains_only_submitted_progress_for_omitted_updates = function()
    local submitted = {}
    local effects = Effects.new(configuration("system", "system"), {
      set_progress = function(_, value, state)
        submitted[#submitted + 1] = { value = value, state = state }
        return state ~= 1
      end,
    }, {})
    local handled, status = effects:consume({ kind = "progress_changed", value = { progress = 73, state = 1 } })
    Assert.truthy(handled)
    Assert.equal(status, "rejected")
    handled, status = effects:consume({ kind = "progress_changed", value = { state = 3 } })
    Assert.truthy(handled)
    Assert.equal(status, "submitted")
    Assert.equal(submitted[1].value, 73)
    Assert.equal(submitted[2].value, 0)
    Assert.equal(submitted[2].state, 3)
  end,
  host_effects_reject_invalid_or_unavailable_submission_without_repeating_reports = function()
    local effects = Effects.new(configuration("system", "system"), {}, {})
    local handled, status, first = effects:consume({ kind = "notification_requested", value = { body = "bad\nbody" } })
    Assert.truthy(handled)
    Assert.equal(status, "invalid")
    Assert.truthy(first)
    handled, status, first = effects:consume({ kind = "notification_requested", value = { body = "bad\nbody" } })
    Assert.truthy(handled)
    Assert.equal(status, "invalid")
    Assert.equal(first, false)
    handled, status = effects:consume({ kind = "progress_changed", value = { progress = 101, state = 1 } })
    Assert.truthy(handled)
    Assert.equal(status, "invalid")
    handled, status = effects:consume({ kind = "progress_changed", value = { state = 1 } })
    Assert.truthy(handled)
    Assert.equal(status, "invalid")
    handled, status = effects:consume({ kind = "progress_changed", value = { progress = 50, state = 1 } })
    Assert.truthy(handled)
    Assert.equal(status, "unavailable")
  end,
}
