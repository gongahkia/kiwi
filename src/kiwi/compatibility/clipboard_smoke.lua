local Window = require("kiwi.platform.window")

local maximum_bytes = 1024 * 1024
local probe = "kiwi-compatibility-clipboard-✓"

local function require_result(value, message)
  assert(value, message)
end

local window
local original
local restore_required = false
local ok, message = xpcall(function()
  window = Window.new(320, 200, "Kiwi clipboard qualification", { release_mode = true, visible = false })
  if jit.os == "OSX" then
    local copied, status = window:cocoa_private_clipboard_round_trip(probe)
    require_result(copied, "Cocoa private pasteboard round trip failed: " .. tostring(status))
    io.stdout:write("Kiwi clipboard qualification passed: private Cocoa pasteboard round trip.\n")
    return
  end

  require_result(os.getenv("KIWI_COMPAT_ALLOW_PUBLIC_CLIPBOARD") == "1", "Linux public clipboard qualification needs --allow-public-clipboard")
  local status
  original, status = window:clipboard_read(maximum_bytes)
  require_result(original ~= nil, "could not preserve the existing public clipboard: " .. tostring(status))
  local written, write_status = window:clipboard_write(probe)
  require_result(written, "could not write the public clipboard: " .. tostring(write_status))
  restore_required = true
  local observed, read_status = window:clipboard_read(maximum_bytes)
  require_result(observed == probe, "public clipboard did not return the qualification value: " .. tostring(read_status))
end, debug.traceback)

local restored, restore_status = true, nil
if restore_required then restored, restore_status = window:clipboard_write(original) end
if window then window:destroy() end
assert(ok, message)
require_result(restored, "could not restore the public clipboard: " .. tostring(restore_status))
if jit.os ~= "OSX" then io.stdout:write("Kiwi clipboard qualification passed: public clipboard restored after round trip.\n") end
