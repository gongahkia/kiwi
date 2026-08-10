local Utf8 = require("kiwi.terminal.utf8")

local Hyperlink = {}

Hyperlink.maximum_uri_bytes = 2048
Hyperlink.maximum_parameter_bytes = 512

local allowed_schemes = {
  http = true,
  https = true,
  mailto = true,
}

local function valid_utf8(value)
  local valid = true
  local decoder = Utf8.Decoder.new(function(_, _, replaced)
    if replaced then valid = false end
  end)
  for index = 1, #value do decoder:feed_byte(value:byte(index)) end
  decoder:finish()
  return valid
end

local function valid_text(value, maximum)
  if type(value) ~= "string" or #value == 0 or #value > maximum or value:find("\0", 1, true) then return false end
  if not valid_utf8(value) then return false end
  for index = 1, #value do
    local byte = value:byte(index)
    if byte <= 0x20 or byte == 0x7f then return false end
  end
  return true
end

function Hyperlink.validate_uri(uri, maximum_bytes)
  maximum_bytes = maximum_bytes or Hyperlink.maximum_uri_bytes
  if not valid_text(uri, maximum_bytes) or uri:find("[^%z\1-\127]") then return nil, "invalid-uri" end
  local scheme = uri:match("^([A-Za-z][A-Za-z0-9+.-]*):")
  if scheme == nil or not allowed_schemes[scheme:lower()] then return nil, "unsupported-scheme" end
  return uri
end

local function parse_parameters(params)
  if params == "" then return nil end
  if #params > Hyperlink.maximum_parameter_bytes then return nil, "parameter-limit" end
  local identifier
  for item in params:gmatch("[^:]+") do
    local key, value = item:match("^([A-Za-z][A-Za-z0-9_.-]*)=([!#-~]+)$")
    if key == nil then return nil, "invalid-parameters" end
    if key == "id" then
      if identifier ~= nil or #value > 128 then return nil, "invalid-parameters" end
      identifier = value
    end
  end
  if params:sub(-1) == ":" then return nil, "invalid-parameters" end
  return identifier
end

function Hyperlink.parse_osc8(payload, maximum_uri_bytes)
  if type(payload) ~= "string" then return nil, "invalid-payload" end
  local params, uri = payload:match("^([^;]*);(.*)$")
  if params == nil then return nil, "invalid-payload" end
  if params == "" and uri == "" then return { kind = "close" } end
  local identifier, parameter_status = parse_parameters(params)
  if parameter_status then return nil, parameter_status end
  local accepted, uri_status = Hyperlink.validate_uri(uri, maximum_uri_bytes)
  if accepted == nil then return nil, uri_status end
  return { id = identifier, kind = "open", uri = accepted }
end

return Hyperlink
