local Assert = require("tests.assert")
local Controller = require("kiwi.app.gtk_gl_controller")
local Session = require("kiwi.app.gtk_gl_session")

return {
  gtk_gl_processes_child_acknowledgment_after_delivering_queued_input = function()
    local queued, delivered, available, parsed = "key", "", "", ""
    local session = {
      read_budget = 4096,
      pty = {
        flush = function()
          if queued == "key" then available = "ack" end
          delivered, queued = delivered .. queued, ""
        end,
        read_available = function() local result = available; available = ""; return result end,
        enqueue = function(_, bytes) queued = queued .. bytes end,
        poll_exit = function() return nil end,
      },
      terminal = {
        write = function(_, bytes) parsed = parsed .. bytes end,
        pop_responses = function() return { "reply" } end,
        pop_effects = function() return {} end,
      },
      _invalidate = function() end,
    }
    Session._drain_terminal(session, 0, true)
    Assert.equal(parsed, "ack")
    Assert.equal(delivered, "keyreply")
    Assert.equal(queued, "")
  end,
  gtk_gl_hidden_page_keeps_its_grid_and_resources_until_allocated = function()
    local font = { content_scale = 1 }
    local session = {
      font = font, columns = 80, rows = 24,
      consumer = { destroy = function() error("hidden page resources must be retained") end },
      window = { resized = true, drawable_size = function() return 0, 0 end,
        content_scale = function() return 2, 2 end },
    }
    Session._resize_if_needed(session)
    Assert.equal(session.font, font)
    Assert.equal(session.columns, 80)
    Assert.equal(session.rows, 24)
    Assert.equal(session.window.resized, true)
  end,
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
