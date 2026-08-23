local Window = require("kiwi.platform.gtk_window")

local window
local ok, message = xpcall(function()
  window = Window.new(320, 200, "Kiwi GTK GL area lifecycle smoke")
  local enabled, reason = window:enable_gl_area_probe()
  assert(enabled, "GTK GL area probe could not be enabled: " .. tostring(reason))

  local state
  for _ = 1, 40 do
    window:wait_events(0.01)
    state, reason = window:gl_area_state()
    assert(state, "GTK GL area state was unavailable: " .. tostring(reason))
    if state.realized and state.context_generation >= 1 and state.rendered_frames >= 1 then break end
  end
  assert(state and state.realized, "GTK GL area was not realized")
  assert(state.context_generation >= 1, "GTK GL area did not create a context generation")
  assert(state.rendered_frames >= 1, "GTK GL area did not run its render lifecycle")

  local previous_frames = state.rendered_frames
  local queued
  queued, reason = window:request_gl_area_render()
  assert(queued, "GTK GL area render could not be queued: " .. tostring(reason))
  for _ = 1, 40 do
    window:wait_events(0.01)
    state, reason = window:gl_area_state()
    assert(state, "GTK GL area state was unavailable after queueing: " .. tostring(reason))
    if state.rendered_frames > previous_frames then break end
  end
  assert(state.rendered_frames > previous_frames, "GTK GL area did not render the queued frame")
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
print("GTK GL area lifecycle smoke passed.")
