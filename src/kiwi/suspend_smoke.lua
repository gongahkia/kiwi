-- observe a fixed real PTY acknowledgement after user-initiated system sleep.
local gtk = os.getenv("KIWI_HOST") == "gtk"
local Host = require(gtk and "kiwi.app.gtk_host" or "kiwi.app.glfw_host")
assert(Host.presentation_backend ~= "gtk-gl", "suspend fixture requires WGPU")
local Pty = require("kiwi.process.pty")
local Compositor = require("kiwi.renderer.compositor")
local Json = require("kiwi.bench.json")
local directory = assert(os.getenv("KIWI_TRANSITION_DIRECTORY"))
local spawn, render, await = Pty.spawn, Compositor.render, Host.await_events
local pty, frames = nil, 0
Pty.spawn = function(...) pty = spawn(...); return pty end
Compositor.render = function(self, entries, ...)
  local result, reason = render(self, entries, ...)
  if result then
    assert(#entries == 1, "suspend fixture requires one terminal")
    local model, font, window = entries[1].model, entries[1].renderer.font, self.context.window
    local token, columns, rows = (model.title or ""):match("^kiwi%-transition:(%a+):(%d+):(%d+)$")
    if token then
      for index = 1, #token do
        if model:get(index - 1, 0).glyph ~= token:sub(index, index) then return result, reason end
      end
      frames = frames + 1
      local width, height = window:drawable_size()
      local file = assert(io.open(directory .. "/snapshot.new", "w"))
      assert(file:write(Json.encode({ token = token, frames = frames, columns = model.columns, rows = model.rows,
        child_columns = tonumber(columns), child_rows = tonumber(rows), drawable_width = width, drawable_height = height,
        surface_width = self.context.width, surface_height = self.context.height,
        scale = window:content_scale(), font_scale = font.content_scale })))
      assert(file:close()); assert(os.rename(directory .. "/snapshot.new", directory .. "/snapshot.json"))
    end
  end
  return result, reason
end
Host.await_events = function(application, window, timeout)
  -- bounded test-only polling detects the control file after system resume.
  local result = await(application, window, math.min(timeout, .1))
  local file = io.open(directory .. "/command", "r")
  if file then
    local command = assert(file:read("*a")); file:close(); assert(os.remove(directory .. "/command"))
    if command == "quit" then window:request_close()
    else
      assert(command == "before" or command == "after", "invalid suspend fixture command")
      pty:enqueue(command .. "\n"); pty:flush()
    end
  end
  return result
end
arg = { "--config", directory .. "/kiwi.conf", "--no-restore-layout", "--no-extensions", "--", "python3",
  "src/tests/fixtures/desktop_transition_child.py" }
local ok, message = xpcall(function() require("kiwi.app.main") end, debug.traceback)
Pty.spawn, Compositor.render, Host.await_events = spawn, render, await
assert(ok, message)
