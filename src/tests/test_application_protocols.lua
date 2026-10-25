local Assert = require("tests.assert")
local Color = require("kiwi.terminal.color")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local function terminal(options)
  local state = State.new(8, 3, options)
  return state, Parser.new(state)
end

local function palette(background, accent)
  return { foreground = Color.pack(220, 220, 220, 255), background = Color.pack(background, background, background, 255),
    palette = accent and { [1] = Color.pack(accent, 0, 0, 255) } or nil }
end

return {
  version_query_identifies_kiwi_and_rejects_parameters_or_control_injection = function()
    local state, parser = terminal({ terminal_version = "0.1.0-test+12" })
    parser:feed("\27[>q\27[>0q\27[>1q\27[>0;0q\27[>0 q")
    local replies = state:pop_responses()
    Assert.equal(#replies, 2)
    Assert.equal(replies[1], "\27P>|Kiwi(0.1.0-test+12)\27\\")
    Assert.equal(replies[2], replies[1])
    Assert.equal(state.stats.unknown.csi, 3)
    Assert.equal(pcall(terminal, { terminal_version = "bad\27\\" }), false)
    Assert.equal(pcall(terminal, { terminal_version = string.rep("a", 65) }), false)
  end,
  theme_query_reports_the_configured_terminal_background = function()
    for _, item in ipairs({ { 20, 1 }, { 240, 2 } }) do
      local state, parser = terminal({ colors = palette(item[1]) })
      parser:feed("\27[?996n")
      Assert.equal(state:pop_responses()[1], "\27[?997;" .. item[2] .. "n")
      Assert.equal(state.modes.color_scheme_reporting, false)
    end
  end,
  theme_subscription_only_notifies_for_changed_host_palettes = function()
    local state, parser = terminal({ colors = palette(20) })
    parser:feed("\27[?2031h\27[?2031$p")
    Assert.equal(table.concat(state:pop_responses()), "\27[?2031;1$y")
    state:configure_palette(palette(20))
    Assert.equal(#state:pop_responses(), 0)
    state:configure_palette(palette(240))
    Assert.equal(table.concat(state:pop_responses()), "\27[?997;2n")
    state:configure_palette(palette(240, 120))
    Assert.equal(table.concat(state:pop_responses()), "\27[?997;2n")
    parser:feed("\27[?2031l")
    state:configure_palette(palette(20))
    Assert.equal(#state:pop_responses(), 0)
  end,
  application_colour_changes_do_not_create_notification_feedback = function()
    local state, parser = terminal({ colors = palette(20) })
    parser:feed("\27[?2031h\27]11;#ffffff\7\27]4;1;#ff0000\7")
    Assert.equal(#state:pop_responses(), 0)
    parser:feed("\27[?996n")
    Assert.equal(table.concat(state:pop_responses()), "\27[?997;1n")
  end,
  application_modes_support_query_save_restore_and_resets = function()
    for _, reset in ipairs({ "\27c", "\27[!p" }) do
      local state, parser = terminal()
      parser:feed("\27[?7727;2031h\27[?7727;2031s\27[?7727;2031l\27[?7727;2031r")
      Assert.equal(state:input_modes().application_escape, true)
      parser:feed("\27[?7727$p\27[?2031$p")
      Assert.equal(table.concat(state:pop_responses()), "\27[?7727;1$y\27[?2031;1$y")
      parser:feed(reset .. "\27[?7727$p\27[?2031$p")
      Assert.equal(table.concat(state:pop_responses()), "\27[?7727;2$y\27[?2031;2$y")
      Assert.equal(state:input_modes().application_escape, false)
    end
  end,
  malformed_application_requests_remain_observable_and_do_not_change_modes = function()
    local state, parser = terminal()
    parser:feed("\27[?7727#h\27[?2031#h\27[?996;1n\27[?996$n")
    Assert.equal(#state:pop_responses(), 0)
    Assert.equal(state.modes.application_escape, false)
    Assert.equal(state.modes.color_scheme_reporting, false)
    Assert.equal(state.stats.unknown.csi, 4)
  end,
}
