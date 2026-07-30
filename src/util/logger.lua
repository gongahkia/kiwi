local serializer = require("src.util.serializer")

local logger = {}
local instance = {}
instance.__index = instance

function logger.new(sink)
  if type(sink) ~= "function" then
    return nil, { code = "invalid_sink", message = "logger sink must be a function" }
  end
  return setmetatable({ sink = sink }, instance)
end

function instance:write(level, category, message, fields)
  if type(level) ~= "string" or type(category) ~= "string" or type(message) ~= "string" then
    return nil,
      { code = "invalid_log_record", message = "level, category, and message must be strings" }
  end
  local record = { level = level, category = category, message = message }
  if fields ~= nil then
    record.fields = fields
  end
  local encoded, err = serializer.encode(record)
  if not encoded then
    return nil, err
  end
  local ok, sink_error = pcall(self.sink, encoded .. "\n")
  if not ok then
    return nil, { code = "sink_failed", message = tostring(sink_error) }
  end
  return true
end

return logger
