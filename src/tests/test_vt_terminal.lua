local Assert = require("tests.assert")
local Terminal = require("kiwi.vt.terminal")

return {
  vt_terminal_exposes_a_bounded_host_neutral_effect_boundary = function()
    local seen = {}
    local terminal = Terminal.new({
      columns = 4,
      rows = 2,
      effects = {
        any = function(effect)
          seen[#seen + 1] = effect
        end,
      },
    })
    terminal:write("\7\27]2;Kiwi\7\27[5n\27]7;file:///tmp\7\27]133;A\7")
    Assert.equal(seen[1].kind, "bell")
    Assert.equal(seen[2].kind, "title_changed")
    Assert.equal(seen[2].value.title, "Kiwi")
    Assert.equal(seen[3].kind, "write_pty")
    Assert.equal(terminal:pop_responses()[1], "\27[0n")
    Assert.equal(seen[4].kind, "pwd_changed")
    Assert.equal(seen[4].value.uri, "file:///tmp")
    Assert.equal(seen[5].kind, "shell_marker")
    Assert.equal(seen[5].value.kind, "prompt")
    Assert.equal(terminal.state:pop_responses()[1], nil)
  end,
  vt_terminal_prevents_reentrant_writes_from_effect_callbacks = function()
    local terminal
    terminal = Terminal.new({
      columns = 2,
      rows = 1,
      effects = {
        bell = function()
          terminal:write("x")
        end,
      },
    })
    terminal:write("\7")
    local diagnostics = terminal:diagnostics()
    Assert.equal(#diagnostics.effect_errors, 1)
    Assert.equal(terminal.state:get(0, 0).glyph, " ")
  end,
  vt_terminal_render_updates_provide_read_only_cell_copies_and_explicit_damage_acknowledgement = function()
    local terminal = Terminal.new({ columns = 3, rows = 1 })
    terminal:write("A")
    local view = terminal:begin_render_update()
    Assert.truthy(view.damage.cells > 0)
    Assert.equal(view:cell(0, 0).glyph, "A")
    local copied = view:cell(0, 0)
    copied.glyph = "X"
    Assert.equal(terminal.state:get(0, 0).glyph, "A")
    terminal:end_render_update(true)
    Assert.equal(terminal.state.damage.dirty_count, 0)
  end,
  vt_terminal_preserves_parser_continuations_and_reports_them_at_finish = function()
    local terminal = Terminal.new({ columns = 2, rows = 1 })
    terminal:write("\27]2;incomplete")
    terminal:finish()
    Assert.equal(terminal.parser.stats.errors, 1)
    Assert.equal(terminal.state.stats.unknown.osc, 1)
  end,
}
