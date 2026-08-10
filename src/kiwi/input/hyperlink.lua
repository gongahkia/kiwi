local TerminalHyperlink = require("kiwi.terminal.hyperlink")

local Hyperlink = {}
Hyperlink.__index = Hyperlink

function Hyperlink.new(platform)
  assert(type(platform) == "table" and type(platform.open_uri) == "function", "hyperlink activation needs a URI opener")
  return setmetatable({
    platform = platform,
    counters = { activated = 0, no_link = 0, rejected = 0, unavailable = 0 },
  }, Hyperlink)
end

function Hyperlink:activate(link)
  if type(link) ~= "table" then
    self.counters.no_link = self.counters.no_link + 1
    return false, "no-link"
  end
  local uri = TerminalHyperlink.validate_uri(link.uri)
  if uri == nil then
    self.counters.rejected = self.counters.rejected + 1
    return false, "invalid-uri"
  end
  local opened, status = self.platform:open_uri(uri)
  if not opened then
    self.counters.unavailable = self.counters.unavailable + 1
    return false, status or "unavailable"
  end
  self.counters.activated = self.counters.activated + 1
  return true
end

function Hyperlink:snapshot()
  return { counters = self.counters }
end

return Hyperlink
