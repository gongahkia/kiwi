local Errors = require("runtime.errors")

local Clean = {}

Clean.id = "stanczyk.clean"
Clean.contract = {
  new = "new(options?) -> preset | nil, error",
}

function Clean.new(options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return nil, Errors.new("config_error", "clean renderer options must be a table")
  end
  for name in pairs(options) do
    return nil, Errors.new("config_error", "unknown clean renderer option", { option = name })
  end
  return {
    effects = {},
    id = Clean.id,
    post_processing = false,
  }
end

return Clean
