local Assert = require("tests.assert")
local Actions = require("kiwi.app.actions")
local glfw = require("kiwi.ffi.glfw").constants

return {
  product_action_defaults_preserve_workspace_shortcuts = function()
    local actions = Actions.new({}, glfw)
    Assert.equal(actions:lookup(string.byte("T"), glfw.mod_control + glfw.mod_shift), "new-tab")
    Assert.equal(actions:lookup(glfw.key_enter, glfw.mod_control + glfw.mod_shift), "split-right")
    Assert.equal(actions:lookup(string.byte("P"), glfw.mod_control + glfw.mod_shift), "command-palette")
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
  product_actions_support_bounded_non_ambiguous_key_sequences = function()
    local actions = Actions.new({
      Actions.parse("clear", "test"),
      Actions.parse("ctrl+a > n = new-window", "test"),
      Actions.parse("ctrl+a > ctrl+n > t = new-tab", "test"),
    }, glfw)
    local action, status = actions:lookup(string.byte("A"), glfw.mod_control, 1)
    Assert.equal(action, nil)
    Assert.equal(status, "pending")
    Assert.equal(actions:lookup(string.byte("N"), 0, 1.1), "new-window")
    action, status = actions:lookup(string.byte("A"), glfw.mod_control, 2)
    Assert.equal(action, nil)
    Assert.equal(status, "pending")
    action, status = actions:lookup(string.byte("N"), glfw.mod_control, 2.1)
    Assert.equal(action, nil)
    Assert.equal(status, "pending")
    Assert.equal(actions:lookup(string.byte("T"), 0, 2.2), "new-tab")
    action, status = actions:lookup(string.byte("A"), glfw.mod_control, 3)
    Assert.equal(action, nil)
    Assert.equal(status, "pending")
    Assert.equal(actions:lookup(string.byte("N"), 0, 4.1), nil)
    Assert.equal(actions:bindings_view()[1].binding, "65:2>78:0")
  end,
  product_actions_reject_ambiguous_or_overlong_key_sequences = function()
    Assert.truthy(not pcall(Actions.parse, "ctrl+a>b>c>d=new-tab", "test"))
    Assert.truthy(not pcall(Actions.parse, "ctrl+a>=new-tab", "test"))
    Assert.truthy(not pcall(function()
      Actions.new({ Actions.parse("clear", "test"), Actions.parse("ctrl+a=new-tab", "test"), Actions.parse("ctrl+a>b=new-window", "test") }, glfw)
    end))
    Assert.truthy(not pcall(function()
      Actions.new({ Actions.parse("clear", "test"), Actions.parse("ctrl+a>b=new-window", "test"), Actions.parse("ctrl+a=new-tab", "test") }, glfw)
    end))
  end,
  product_actions_clear_defaults_without_accepting_unknown_actions_or_keys = function()
    local actions = Actions.new({ Actions.parse("clear", "test") }, glfw)
    Assert.equal(actions:lookup(glfw.key_f6, 0), nil)
    Assert.truthy(not pcall(Actions.parse, "ctrl+shift+t = launch-shell", "test"))
    Assert.truthy(not pcall(Actions.parse, "ctrl+banana = new-tab", "test"))
    Assert.truthy(not pcall(Actions.parse, "ctrl+f13 = new-tab", "test"))
  end,
  product_action_palette_is_bounded_detached_and_excludes_the_palette_opener = function()
    local entries = Actions.palette_entries()
    Assert.equal(#entries, 12)
    Assert.equal(entries[1].action, "new-tab")
    Assert.truthy(entries[1].title ~= "")
    Assert.truthy(entries[1].description ~= "")
    entries[1].title = "mutated"
    Assert.equal(Actions.palette_entries()[1].title, "New Tab")
    local configuration_entry = false
    for _, entry in ipairs(entries) do
      Assert.truthy(entry.action ~= "command-palette")
      if entry.action == "open-configuration" then configuration_entry = true end
    end
    Assert.truthy(configuration_entry)
  end,
  product_action_palette_accepts_bounded_custom_entries_and_clear = function()
    local custom = Actions.parse_palette_entry([[title:"Reload, safely", description:"Reload the trusted \"theme\".", action:reload-config]], "test")
    local entries = Actions.palette_entries({ custom })
    Assert.equal(#entries, 13)
    Assert.equal(entries[13].title, "Reload, safely")
    Assert.equal(entries[13].description, [[Reload the trusted "theme".]])
    entries = Actions.palette_entries({ Actions.parse_palette_entry("", "test"), custom })
    Assert.equal(#entries, 1)
    Assert.equal(entries[1].action, "reload-config")
  end,
  product_action_palette_rejects_unsafe_or_malformed_custom_entries = function()
    Assert.truthy(not pcall(Actions.parse_palette_entry, "title:Loop, action:command-palette", "test"))
    Assert.truthy(not pcall(Actions.parse_palette_entry, "title:Unknown, action:launch-shell", "test"))
    Assert.truthy(not pcall(Actions.parse_palette_entry, "title:Only a title", "test"))
    Assert.truthy(not pcall(Actions.parse_palette_entry, "title:\255, action:new-tab", "test"))
    Assert.truthy(not pcall(Actions.parse_palette_entry, "title:Bad, action:new-tab, action:close-pane", "test"))
    Assert.truthy(not pcall(Actions.parse_palette_entry, "title:Bad, action:new-tab,", "test"))
  end,
  product_action_palette_enforces_its_final_entry_limit_after_clear = function()
    local custom = Actions.parse_palette_entry("title:New, action:new-tab", "test")
    local configured = { Actions.parse_palette_entry("", "test") }
    for _ = 1, Actions.maximum_palette_entries do configured[#configured + 1] = custom end
    Assert.equal(#Actions.palette_entries(configured), Actions.maximum_palette_entries)
    configured[#configured + 1] = custom
    Assert.truthy(not pcall(Actions.palette_entries, configured))
  end,
}
