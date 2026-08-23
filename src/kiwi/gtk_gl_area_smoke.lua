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
    cell_updates = {
      { data = cell, first = 0, cell_count = 1 },
    },
    cell_count = 1,
    frame = frame,
    glyph_count = 1,
    glyphs = glyph,
    atlas_bytes = 1,
    atlas_height = 1,
    atlas_pixels = atlas,
    atlas_width = 1,
    revision = 2,
    resource_flags = 7,
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

  local subrange_uploads = state.cell_subrange_uploads
  local subrange_bytes = state.cell_subrange_bytes
  cell[0].bg = 0xff1565c0
  submitted, reason = window:submit_gl_area_snapshot({
    cell_updates = {
      { data = cell, first = 0, cell_count = 1 },
    },
    cell_count = 1,
    frame = frame,
    glyph_count = 1,
    revision = 3,
  })
  assert(submitted, "GTK GL renderer rejected the incremental LuaJIT snapshot: " .. tostring(reason))
  for _ = 1, 40 do
    window:wait_events(0.01)
    state, reason = window:gl_area_state()
    assert(state, "GTK GL area state was unavailable after an incremental update: " .. tostring(reason))
    if state.rendered_revision == 3 and state.cell_subrange_uploads > subrange_uploads then break end
  end
  assert(state.rendered_revision == 3, "GTK GL renderer did not acknowledge the incremental snapshot revision")
  assert(state.cell_subrange_uploads > subrange_uploads,
    "GTK GL renderer did not use a cell subrange upload for the incremental snapshot")
  assert(state.cell_subrange_bytes == subrange_bytes + ffi.sizeof("KiwiGlyphInstance"),
    "GTK GL renderer did not report the expected incremental cell byte count")

  local tabbed
  tabbed, reason = window:enable_native_tabs()
  assert(tabbed, "GTK native-tab container could not attach the primary terminal presentation: " .. tostring(reason))
  local second = window:new_native_tab("Kiwi GTK GL second terminal")
  assert(window:native_tab_count() == 2,
    "GTK native-tab container did not retain two independent terminal presentations")
  for _ = 1, 40 do
    window:wait_events(0.01)
    state, reason = second:gl_area_state()
    assert(state, "second GTK GL terminal state was unavailable: " .. tostring(reason))
    if state.realized and state.context_generation >= 1 and state.rendered_frames >= 1 then break end
  end
  assert(state and state.realized, "second GTK GL terminal presentation was not realized")
  assert(state.context_generation >= 1 and state.rendered_frames >= 1,
    "second GTK GL terminal presentation did not run its own render lifecycle")
  local closed
  closed, reason = second:close_native_tab()
  assert(closed, "GTK native-tab container could not close a non-primary terminal presentation: " .. tostring(reason))
  assert(window:native_tab_count() == 1,
    "GTK native-tab container did not release the closed terminal presentation")
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
print("GTK GL area lifecycle smoke passed.")
