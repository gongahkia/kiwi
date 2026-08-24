local Assert = require("tests.assert")
local Manager = require("kiwi.session.window_manager")

return {
  window_manager_moves_live_sessions_and_duplicates_fresh_sessions = function()
    local next_session = 0
    local manager = Manager.new({ new_session = function() next_session = next_session + 1; return { id = next_session } end })
    local first, first_pane = assert(manager:new_window())
    local second = assert(manager:new_window())
    local moved = assert(manager:move_pane(first.id, first_pane.id, second.id, nil))
    Assert.equal(moved.session.id, 1)
    Assert.equal(first.workspace:pane_count(), 0)
    Assert.equal(second.workspace:pane_count(), 2)
    local duplicate = assert(manager:duplicate_pane(second.id, second.id, moved.tab_id))
    Assert.equal(duplicate.session.id, 3)
    Assert.equal(next_session, 3)
  end,
  window_manager_bounds_windows_and_snapshots_only_layout = function()
    local manager = Manager.new({ maximum_windows = 1, new_session = function() return {} end })
    local first = assert(manager:new_window({ geometry = { height = 800, width = 1200, x = 40, y = 50 } }))
    local second, reason = manager:new_window()
    Assert.equal(second, nil)
    Assert.equal(reason, "window-limit")
    local snapshot = manager:snapshot()
    Assert.equal(snapshot.schema_version, 2)
    Assert.equal(snapshot.windows[1].id, nil)
    Assert.equal(snapshot.windows[1].geometry.width, 1200)
    Assert.equal(snapshot.windows[1].workspace.tabs[1].pane_count, 1)
    Assert.equal(snapshot.windows[1].workspace.tabs[1].root.kind, "leaf")
    Assert.truthy(snapshot.windows[1].workspace.tabs[1].root.session == nil)
    Assert.equal(first.id, 1)
  end,
}
