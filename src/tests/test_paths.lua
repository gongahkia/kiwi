local Assert = require("tests.assert")
local Paths = require("kiwi.paths")

return {
  runtime_paths_use_the_checkout_source_tree_by_default = function()
    Assert.equal(Paths.lua_root(function(name) return name == "KIWI_ROOT" and "/source" or nil end), "/source/src")
  end,
  runtime_paths_allow_packaged_lua_assets_without_rewriting_the_root = function()
    Assert.equal(Paths.lua_root(function(name)
      if name == "KIWI_ROOT" then return "/package" end
      if name == "KIWI_LUA_ROOT" then return "/package/share/kiwi/lua" end
    end), "/package/share/kiwi/lua")
  end,
}
