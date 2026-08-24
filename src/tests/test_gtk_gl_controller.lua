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
  gtk_gl_controller_defers_resize_while_the_drawable_is_zero = function()
    local window = {
      resized = true,
      drawable_size = function() return 0, 480 end,
    }
    local grid = Controller.next_grid(window, { cell_width = 10, cell_height = 20 }, 80, 24)
    Assert.equal(grid, nil)
  end,
  gtk_gl_controller_keeps_resize_information_for_the_next_positive_drawable = function()
    local window = {
      resized = true,
      drawable_size = function() return 800, 480 end,
    }
    local grid = assert(Controller.next_grid(window, { cell_width = 10, cell_height = 20 }, 80, 24))
    Assert.equal(grid.columns, 80)
    Assert.equal(grid.rows, 24)
    Assert.equal(grid.resize, true)
  end,
}
