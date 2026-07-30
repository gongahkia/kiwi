local assertions = require("support.assertions")
local Backend = require("backend.interface")

local function backend_method()
  return {}
end

return {
  {
    name = "backend contract accepts complete implementations",
    run = function()
      local candidate = {
        start = backend_method,
        poll = backend_method,
        send_input = backend_method,
        resize = backend_method,
        stop = backend_method,
        capabilities = backend_method,
        status = backend_method,
      }
      assertions.equal(candidate, assert(Backend.validate(candidate)))
    end,
  },
  {
    name = "backend contract rejects missing methods",
    run = function()
      local backend, error_value = Backend.validate({})
      assertions.falsy(backend)
      assertions.equal("backend_protocol_error", error_value.kind)
    end,
  },
}
