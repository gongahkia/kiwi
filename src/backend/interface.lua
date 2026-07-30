local Errors = require("runtime.errors")

local Backend = {}

local required_methods = {
  "start",
  "poll",
  "send_input",
  "resize",
  "stop",
  "capabilities",
  "status",
}

Backend.contract = {
  start = "start(config?) -> nil, error?",
  poll = "poll(now_us) -> ordered_events | nil, error?",
  send_input = "send_input(bytes) -> nil, error?",
  resize = "resize(columns, rows, pixel_width?, pixel_height?) -> nil, error?",
  stop = "stop(reason?) -> nil, error?",
  capabilities = "capabilities() -> table",
  status = "status() -> table",
}

function Backend.validate(candidate)
  if type(candidate) ~= "table" then
    return nil, Errors.new("backend_protocol_error", "backend must be a table")
  end
  for _, method in ipairs(required_methods) do
    if type(candidate[method]) ~= "function" then
      return nil, Errors.new("backend_protocol_error", "backend is missing method: " .. method)
    end
  end
  return candidate
end

return Backend
