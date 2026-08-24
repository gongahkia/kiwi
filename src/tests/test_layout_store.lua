local Assert = require("tests.assert")
local Store = require("kiwi.session.layout_store")

return {
  layout_store_accepts_only_bounded_non_sensitive_topology = function()
    local snapshot = {
      schema_version = 2,
      windows = {
        { geometry = { height = 800, width = 1200, x = 1, y = 2 }, workspace = {
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
      schema_version = 2,
      windows = {
        { geometry = { height = 800, width = 1200, x = 1, y = 2 }, workspace = {
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
  layout_store_migrates_only_valid_v1_geometry_and_topology = function()
    local legacy = {
      schema_version = 1,
      windows = {
        { id = 7, geometry = { height = 800, width = 1200, x = 1, y = 2 }, workspace = {
          active_tab_id = 4,
          tabs = { { active_pane_id = 5, id = 4, root = { kind = "leaf", pane_id = 5 } } },
        } },
      },
    }
    Assert.equal(Store.validate(legacy), nil)
    local migrated, changed = assert(Store.migrate(legacy))
    Assert.truthy(changed)
    Assert.equal(migrated.schema_version, 2)
    Assert.equal(migrated.windows[1].id, nil)
    Assert.equal(migrated.windows[1].workspace.tabs[1].root.pane_id, 5)

    local path = os.tmpname() .. "-kiwi-v1-layout"
    os.remove(path)
    local file = assert(io.open(path, "wb"))
    assert(file:write(require("kiwi.bench.json").encode(legacy)))
    assert(file:close())
    local loaded, _, loaded_changed = assert(Store.load(path))
    Assert.truthy(loaded_changed)
    Assert.equal(loaded.schema_version, 2)
    os.remove(path)

    legacy.windows[1].workspace.tabs[1].root.session = { secret = "not layout" }
    Assert.equal(Store.migrate(legacy), nil)
  end,
  layout_store_rejects_malformed_and_future_schema_without_restore = function()
    local malformed = { schema_version = 1, windows = {} }
    local migrated, reason = Store.migrate(malformed)
    Assert.equal(migrated, nil)
    Assert.equal(reason, "invalid-layout")
    migrated, reason = Store.migrate({ schema_version = 3, windows = {} })
    Assert.equal(migrated, nil)
    Assert.equal(reason, "unsupported-layout-version")
    local path = os.tmpname() .. "-kiwi-future-layout"
    os.remove(path)
    local file = assert(io.open(path, "wb"))
    assert(file:write('{"schema_version":3,"windows":[]}'))
    assert(file:close())
    local loaded, load_reason = Store.load(path)
    Assert.equal(loaded, nil)
    Assert.equal(load_reason, "unsupported-layout-version")
    os.remove(path)
  end,
  layout_store_uses_platform_state_paths = function()
    local environment = function(name) return name == "HOME" and "/home/kiwi" or name == "XDG_STATE_HOME" and "/state" or nil end
    Assert.equal(Store.path(environment, "Linux"), "/state/kiwi/workspace-v2.json")
    Assert.equal(Store.path(environment, "OSX"), "/home/kiwi/Library/Application Support/io.github.gongahkia.kiwi/workspace-v2.json")
    Assert.equal(Store.legacy_path(environment, "Linux"), "/state/kiwi/workspace-v1.json")
    Assert.equal(Store.legacy_path(environment, "OSX"), "/home/kiwi/Library/Application Support/io.github.gongahkia.kiwi/workspace-v1.json")
  end,
}
