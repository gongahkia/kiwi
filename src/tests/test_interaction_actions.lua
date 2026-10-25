local Assert = require("tests.assert")
local Interaction = require("kiwi.app.interaction_actions")
local Terminal = require("kiwi.session.terminal")
local Clipboard = require("kiwi.input.clipboard")
local Workspace = require("kiwi.session.workspace")

return {
  interaction_host_abi_matches_the_lua_catalogue_without_duplicate_ids = function()
    local file = assert(io.open("native/interaction_actions.def", "r"))
    local source = file:read("*a"); file:close()
    local entries, count = {}, 0
    for id, action in source:gmatch('KIWI_INTERACTION_ACTION%((%d+),%s*[%w_]+,%s*"([%w%-]+)"%)') do
      Assert.equal(entries[action], nil)
      entries[action], count = tonumber(id), count + 1
    end
    Assert.equal(count, #Interaction.entries)
    local ids = {}
    for _, entry in ipairs(Interaction.entries) do
      Assert.equal(entries[entry.action], entry.id)
      Assert.equal(ids[entry.id], nil)
      Assert.truthy(entry.id > 28)
      ids[entry.id] = true
    end
  end,
  interaction_terminal_actions_use_selection_paste_modes_and_history_scope = function()
    local terminal = Terminal.new({ columns = 12, rows = 2 })
    terminal:write("old\r\nlive\r\ncurrent\27[?2004h")
    local state, written, queued = Terminal.state(terminal)
    local clipboard = Clipboard.new({
      clipboard_read = function() return "hello\nworld" end,
      clipboard_write = function(_, text) written = text; return true end,
    })
    local function action(name) return Interaction.terminal(name, state, clipboard, function(text) queued = text end) end
    Assert.truthy(action("select-all"))
    Assert.truthy(action("copy"))
    Assert.equal(written, "old\nlive\ncurrent")
    Assert.truthy(action("paste"))
    Assert.equal(queued, "\27[200~hello\nworld\27[201~")
    action("scroll-to-top")
    Assert.equal(state.history_offset, state.scrollback:size())
    action("scroll-to-bottom")
    Assert.equal(state.history_offset, 0)
    action("search")
    state:search_append("live")
    Assert.truthy(action("search-next"))
    Assert.equal(state:search_view().match_count, 1)
    Assert.truthy(action("search-previous"))
    Assert.truthy(action("clear-scrollback"))
    Assert.equal(state.scrollback:size(), 0)
  end,
  interaction_actions_resize_focus_and_bound_font_zoom = function()
    local workspace = Workspace.new()
    local first = workspace:new_tab("one")
    workspace:split("vertical", "two")
    Assert.truthy(Interaction.workspace("focus-pane-left", workspace, 80, 24))
    Assert.equal(workspace:active_pane().id, first.id)
    Assert.truthy(Interaction.workspace("resize-pane-right", workspace, 80, 24))
    Assert.equal(workspace:layout(80, 24)[1].width, 42)
    Assert.truthy(Interaction.workspace("toggle-pane-zoom", workspace, 80, 24))
    Assert.equal(#workspace:layout(80, 24), 1)
    local changed, reason = Interaction.workspace("toggle-pane-zoom", workspace, 1, 1)
    Assert.equal(changed, nil)
    Assert.equal(reason, "insufficient-space")
    Assert.equal(workspace:active_tab().zoomed, true)
    Assert.truthy(Interaction.workspace("toggle-pane-zoom", workspace, 80, 24))
    Assert.equal(#workspace:layout(80, 24), 2)
    Assert.equal(Interaction.font_target("increase-font-size", 256, 18), 256)
    Assert.equal(Interaction.font_target("decrease-font-size", 1, 18), 1)
    Assert.equal(Interaction.font_target("reset-font-size", 20, 18), 18)
  end,
}
