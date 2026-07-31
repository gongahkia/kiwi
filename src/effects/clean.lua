local Effect = require("effects.effect")

local Clean = {}

Clean.id = "stanczyk.clean"

function Clean.new()
  return Effect.new({
    api_version = 1,
    capabilities = {},
    determinism = "static",
    id = Clean.id,
    parameters = {},
    version = "0.1.0",
  })
end

return Clean
