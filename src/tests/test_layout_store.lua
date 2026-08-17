local Assert = require("tests.assert")
local Store = require("kiwi.session.layout_store")

return {
  layout_store_accepts_only_bounded_non_sensitive_topology = function()
    local snapshot = {
      schema_version = 1,
      windows = {
        { id = 1, geometry = { height = 800, width = 1200, x = 1, y = 2 }, workspace = {
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
  layout_store_uses_platform_state_paths = function()
    local environment = function(name) return name == "HOME" and "/home/kiwi" or name == "XDG_STATE_HOME" and "/state" or nil end
    Assert.equal(Store.path(environment, "Linux"), "/state/kiwi/workspace-v1.json")
    Assert.equal(Store.path(environment, "OSX"), "/home/kiwi/Library/Application Support/io.github.gongahkia.kiwi/workspace-v1.json")
  end,
}
