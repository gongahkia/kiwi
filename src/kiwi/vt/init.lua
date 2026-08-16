-- Experimental host-neutral terminal API. This module intentionally imports no
-- PTY, window, GPU, font, or clipboard implementation.
local Terminal = require("kiwi.vt.terminal")
local Input = require("kiwi.vt.input")

local VT = {
  api_version = Terminal.api_version,
  Input = Input,
  Terminal = Terminal,
}

function VT.new(options)
  return Terminal.new(options)
end

return VT
