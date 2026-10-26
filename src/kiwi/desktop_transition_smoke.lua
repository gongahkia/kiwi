-- Observe actual window/renderer/PTY state in an externally controlled compositor.
assert(os.getenv("KIWI_TRANSITION_ISOLATED") == "1", "transitions require an isolated desktop")
local Host = require("kiwi.app.gtk_host")
local Compositor = require("kiwi.renderer.compositor")
local Consumer = require("kiwi.renderer.gtk_gl_consumer")
local Json = require("kiwi.bench.json")
local root = assert(os.getenv("KIWI_TRANSITION_DIRECTORY"))
local render, gl_render, await = Compositor.render, Consumer.render, Host.await_events
local started, frames, pending = nil, 0, nil
local function capture(model, font, window, surface_width, surface_height)
  local token, columns, rows = (model.title or ""):match("^kiwi%-transition:(%a+):(%d+):(%d+)$")
  if not token then return nil end
  for index = 1, #token do
    if model:get(index - 1, 0).glyph ~= token:sub(index, index) then return nil end
  end
  local width, height = window:drawable_size()
  return { token = token, columns = model.columns, rows = model.rows,
    child_columns = tonumber(columns), child_rows = tonumber(rows), drawable_width = width,
    drawable_height = height, surface_width = surface_width or width, surface_height = surface_height or height,
    scale = window:content_scale(), logical_width = window.width, logical_height = window.height,
    font_scale = font.content_scale, cell_width = font.cell_width, cell_height = font.cell_height }
end
local function save(snapshot)
  if not snapshot then return end
  frames = frames + 1
  snapshot.frames = frames
  local file = assert(io.open(root .. "/snapshot.new", "w"))
  assert(file:write(Json.encode(snapshot))); assert(file:close())
  assert(os.rename(root .. "/snapshot.new", root .. "/snapshot.json"))
end
Compositor.render = function(self, entries, ...)
  local result, reason = render(self, entries, ...)
  if result then
    assert(#entries == 1, "transition fixture requires one pane")
    save(capture(entries[1].model, entries[1].renderer.font, self.context.window, self.context.width, self.context.height))
  end
  return result, reason
end
Consumer.render = function(self, model, ...)
  local result, reason = gl_render(self, model, ...)
  if result then
    pending = capture(model, self.prepared_frame.font, self.window)
    if pending then pending.revision = self.revision - 1 end
  end
  return result, reason
end
Host.await_events = function(application, window, timeout)
  started = started or window:time()
  assert(window:time() - started < 90, "desktop transition fixture exceeded its deadline")
  local command = io.open(root .. "/quit", "r")
  if command then command:close(); window:request_close() end
  -- Test-only control-file polling. Production scheduling is unchanged.
  await(application, window, math.min(timeout, 0.01))
  if pending then
    local state = assert(window:gl_area_state())
    if state.rendered_revision == pending.revision then
      pending.native_rendered_frames = state.rendered_frames
      save(pending)
      pending = nil
    end
  end
end
arg = { "--config", root .. "/kiwi.conf", "--no-restore-layout", "--no-extensions", "--", "python3",
  "src/tests/fixtures/desktop_transition_child.py" }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Compositor.render, Consumer.render, Host.await_events = render, gl_render, await
assert(ok, message)
