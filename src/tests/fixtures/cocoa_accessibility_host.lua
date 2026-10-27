-- Runs the real controller, parser and native accessibility bridge. Only the
-- owned test window's size/visibility are controlled; no text model is injected.
local Window = require("kiwi.platform.window")
local Host = require("kiwi.app.glfw_host")
local ffi = require("ffi")
ffi.cdef[[void kiwi_accessibility_fixture_show(void *window);]]
local native = ffi.load(assert(os.getenv("KIWI_AX_FIXTURE_LIB")))
local create, await, shown = Window.new, Host.await_events, false
Window.new = function(_, _, title, options) return create(800, 480, title, options) end
Host.await_events = function(app, window, timeout)
  if not shown then native.kiwi_accessibility_fixture_show(window.handle); shown = true end
  return await(app, window, timeout)
end
require("kiwi.app.main")
