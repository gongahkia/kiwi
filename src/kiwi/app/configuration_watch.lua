local Utf8 = require("kiwi.terminal.utf8")
local Watch = {}
Watch.__index = Watch

function Watch.new()
  return setmetatable({ delay = 0.2 }, Watch)
end

function Watch:observe(changed, now)
  if changed then self.deadline = now + self.delay end
end

function Watch:ready(now)
  if not self.deadline or now < self.deadline then return false end
  self.deadline = nil
  return true
end

function Watch:acknowledge()
  self.deadline = nil
end

function Watch:set_error(message)
  if message == nil then self.error = nil; return end
  message = tostring(message):match("^[^\r\n]*") or "configuration reload failed"
  message = message:gsub("^.-:%d+: ", "")
  local parts, count = {}, 0
  local decoder = Utf8.Decoder.new(function(codepoint, text)
    count = count + 1
    if count <= 160 then parts[#parts + 1] = (codepoint < 32 or codepoint == 127) and " " or text end
  end)
  for index = 1, #message do decoder:feed_byte(message:byte(index)) end
  decoder:finish()
  self.error = table.concat(parts) .. (count > 160 and "…" or "")
end

function Watch:title(title)
  if not self.error then return title end
  return "Kiwi — Configuration error: " .. self.error .. " — " .. title
end

return Watch
