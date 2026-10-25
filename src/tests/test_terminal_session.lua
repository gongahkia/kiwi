local Assert = require("tests.assert")
local Terminal = require("kiwi.session.terminal")

return {
  terminal_session_preserves_chunked_unicode_and_separates_host_effects = function()
    local terminal = Terminal.new({ columns = 8, rows = 2 })
    terminal:write("A\231")
    terminal:write("\149\140\27]2;title\7\27[5n")
    Assert.equal(Terminal.state(terminal):get(1, 0).glyph, "界")
    Assert.equal(Terminal.state(terminal):get(2, 0).continuation, true)
    Assert.equal(terminal:pop_responses()[1], "\27[0n")
    local effects = terminal:pop_effects()
    Assert.equal(effects[1].kind, "title_changed")
    Assert.equal(effects[1].value.title, "title")
    Assert.equal(#terminal:pop_effects(), 0)
    Assert.equal(#terminal:pop_responses(), 0)
  end,
  terminal_session_contains_callback_failures_and_reentrant_writes = function()
    local terminal
    terminal = Terminal.new({ columns = 2, rows = 1, effects = {
      bell = function() terminal:write("x") end,
    } })
    terminal:write("\7ok")
    Assert.equal(#terminal:diagnostics().effect_errors, 1)
    Assert.equal(Terminal.state(terminal):get(0, 0).glyph, "o")
    Assert.equal(Terminal.state(terminal):get(1, 0).glyph, "k")
  end,
  terminal_session_bounds_effect_retention_and_owns_shutdown = function()
    local terminal = Terminal.new({ columns = 2, rows = 1, effect_limit = 2 })
    terminal:write("\7\7\7")
    Assert.equal(#terminal:pop_effects(), 2)
    terminal:close()
    terminal:close()
    Assert.equal(pcall(function() terminal:write("x") end), false)
    Assert.equal(pcall(function() Terminal.state(terminal) end), false)
  end,
  terminal_session_resize_and_cell_metrics_drive_application_replies = function()
    local terminal = Terminal.new({ columns = 4, rows = 2 })
    terminal:resize(8, 3)
    terminal:set_cell_metrics(9, 17)
    terminal:write("\27[14t\27[16t\27[18t")
    local replies = terminal:pop_responses()
    Assert.equal(replies[1], "\27[4;51;72t")
    Assert.equal(replies[2], "\27[6;17;9t")
    Assert.equal(replies[3], "\27[8;3;8t")
    terminal:write("\27]2;incomplete")
    terminal:finish()
    Assert.equal(Terminal.parser(terminal).stats.errors, 1)
  end,
  terminal_session_leaves_clipboard_queries_to_the_host = function()
    local terminal = Terminal.new({ columns = 2, rows = 1, state_options = { osc52_read = true } })
    terminal:write("\27]52;c;?\7")
    local effect = terminal:pop_effects()[1]
    Assert.equal(effect.kind, "clipboard_read_requested")
    Assert.equal(effect.value.maximum_bytes, 64 * 1024)
    Assert.equal(#terminal:pop_responses(), 0)
  end,
}
