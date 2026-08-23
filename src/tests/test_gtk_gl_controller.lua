local Assert = require("tests.assert")
local Controller = require("kiwi.app.gtk_gl_controller")

return {
  gtk_gl_controller_rejects_workspace_features_before_opening_a_terminal = function()
    local accepted, reason = Controller.validate_options({ workspace_smoke = true })
    Assert.equal(accepted, nil)
    Assert.truthy(reason:find("workspace smoke", 1, true) ~= nil)
  end,
  gtk_gl_controller_accepts_a_single_terminal_option_set = function()
    Assert.truthy(Controller.validate_options({ configuration_overrides = {} }))
  end,
}
