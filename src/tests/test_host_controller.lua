local Controller = require("kiwi.app.host_controller")

return {
  host_controller_exposes_the_internal_host_entrypoint = function()
    assert(type(Controller.run) == "function")
  end,
}
