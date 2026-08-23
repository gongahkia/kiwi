local Window = require("kiwi.platform.gtk_window")
local ffi = require("ffi")

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
  assert(state.rendered_revision == 1, "GTK GL renderer did not draw the submitted background snapshot")

  local cell = ffi.new("KiwiGlyphInstance[1]")
  cell[0].bg = 0xff2e7d32
  local glyph = ffi.new("KiwiTextGlyphInstance[1]")
  glyph[0].width = 1
  glyph[0].height = 1
  glyph[0].u1 = 1
  glyph[0].v1 = 1
  glyph[0].fg = 0xffffffff
  glyph[0].glyph = 1
  local atlas = ffi.new("uint8_t[1]", 255)
  local frame = ffi.new("KiwiFrameUniform[1]")
  frame[0].columns = 1
  frame[0].rows = 1
  local submitted
  submitted, reason = window:submit_gl_area_snapshot({
    cell_count = 1,
    cells = cell,
    frame = frame,
    glyph_count = 1,
    glyphs = glyph,
    atlas_bytes = 1,
    atlas_height = 1,
    atlas_pixels = atlas,
    atlas_width = 1,
    revision = 2,
  })
  assert(submitted, "GTK GL renderer rejected the LuaJIT snapshot: " .. tostring(reason))

  local previous_frames = state.rendered_frames
  local queued
  queued, reason = window:request_gl_area_render()
  assert(queued, "GTK GL area render could not be queued: " .. tostring(reason))
  for _ = 1, 40 do
    window:wait_events(0.01)
    state, reason = window:gl_area_state()
    assert(state, "GTK GL area state was unavailable after queueing: " .. tostring(reason))
    if state.rendered_frames > previous_frames and state.rendered_revision == 2 then break end
  end
  assert(state.rendered_frames > previous_frames, "GTK GL area did not render the queued frame")
  assert(state.rendered_revision == 2, "GTK GL renderer did not acknowledge the LuaJIT snapshot revision")
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
print("GTK GL area lifecycle smoke passed.")
