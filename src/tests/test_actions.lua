local Assert = require("tests.assert")
local Actions = require("kiwi.app.actions")
local glfw = require("kiwi.ffi.glfw").constants

return {
  product_action_defaults_preserve_workspace_shortcuts = function()
    local actions = Actions.new({}, glfw)
    Assert.equal(actions:lookup(string.byte("T"), glfw.mod_control + glfw.mod_shift), "new-tab")
    Assert.equal(actions:lookup(glfw.key_enter, glfw.mod_control + glfw.mod_shift), "split-right")
    Assert.equal(actions:lookup(glfw.key_f6, 0), "reload-config")
  end,
  product_actions_replace_and_remove_exact_default_chords = function()
    local actions = Actions.new({
      Actions.parse("ctrl+shift+t = none", "test"),
      Actions.parse("ctrl+alt+t = new-tab", "test"),
      Actions.parse("ctrl+shift+alt+m = move-session-new-window", "test"),
    }, glfw)
    Assert.equal(actions:lookup(string.byte("T"), glfw.mod_control + glfw.mod_shift), nil)
    Assert.equal(actions:lookup(string.byte("T"), glfw.mod_control + glfw.mod_alt), "new-tab")
    Assert.equal(actions:lookup(string.byte("M"), glfw.mod_control + glfw.mod_shift + glfw.mod_alt), "move-session-new-window")
  end,
  product_actions_clear_defaults_without_accepting_unknown_actions_or_keys = function()
    local actions = Actions.new({ Actions.parse("clear", "test") }, glfw)
    Assert.equal(actions:lookup(glfw.key_f6, 0), nil)
    Assert.truthy(not pcall(Actions.parse, "ctrl+shift+t = launch-shell", "test"))
    Assert.truthy(not pcall(Actions.parse, "ctrl+banana = new-tab", "test"))
    Assert.truthy(not pcall(Actions.parse, "ctrl+f13 = new-tab", "test"))
  end,
}
