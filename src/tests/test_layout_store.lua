local Assert = require("tests.assert")
local Store = require("kiwi.session.layout_store")

return {
  layout_store_accepts_only_bounded_non_sensitive_topology = function()
    local snapshot = {
      schema_version = 1,
      windows = {
        { id = 1, geometry = { height = 800, width = 1200, x = 1, y = 2 }, workspace = {
          active_tab_id = 1,
          tabs = { { active_pane_id = 1, id = 1, root = { kind = "leaf", pane_id = 1 } } },
        } },
      },
    }
    Assert.truthy(Store.validate(snapshot))
    local encoded = Store.encode(snapshot)
    Assert.truthy(encoded:find("workspace", 1, true))
    Assert.truthy(not encoded:find("terminal", 1, true))
    snapshot.windows[1].geometry.width = 1
    Assert.equal(Store.validate(snapshot), nil)
  end,
  layout_store_round_trips_bounded_layout_files_and_rejects_extra_data = function()
    local path = os.tmpname() .. "-kiwi-layout"
    os.remove(path)
    local snapshot = {
      schema_version = 1,
      windows = {
        { id = 1, geometry = { height = 800, width = 1200, x = 1, y = 2 }, workspace = {
          active_tab_id = 1,
          tabs = { { active_pane_id = 1, id = 1, root = { kind = "leaf", pane_id = 1 } } },
        } },
      },
    }
    Assert.truthy(Store.write(path, snapshot))
    local loaded = assert(Store.load(path))
    Assert.equal(loaded.windows[1].geometry.width, 1200)
    snapshot.windows[1].workspace.tabs[1].root.session = { secret = "must not persist" }
    Assert.equal(Store.validate(snapshot), nil)
    local corrupt = assert(io.open(path, "wb"))
    assert(corrupt:write("{\"schema_version\":1,"))
    assert(corrupt:close())
    local invalid, reason = Store.load(path)
    Assert.equal(invalid, nil)
    Assert.equal(reason, "invalid-layout")
    os.remove(path)
  end,
  layout_store_uses_platform_state_paths = function()
    local environment = function(name) return name == "HOME" and "/home/kiwi" or name == "XDG_STATE_HOME" and "/state" or nil end
    Assert.equal(Store.path(environment, "Linux"), "/state/kiwi/workspace-v1.json")
    Assert.equal(Store.path(environment, "OSX"), "/home/kiwi/Library/Application Support/io.github.gongahkia.kiwi/workspace-v1.json")
  end,
}
