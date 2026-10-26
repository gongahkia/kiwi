local Assert = require("tests.assert")
local Config = require("kiwi.config")
local Reload = require("kiwi.app.configuration_reload")
local Snapshot = require("kiwi.terminal.snapshot")
local StateTransaction = require("kiwi.terminal.state_transaction")
local Terminal = require("kiwi.session.terminal")
local Workspace = require("kiwi.session.workspace")

local function upload_image(terminal)
  Terminal.state(terminal).kitty_graphics.decoder = { decode = function()
    return { bytes = 4, frame_bytes = 4, format = "png", width = 1, height = 1, plays = 1,
      frames = { { pixels = string.char(255, 0, 0, 255), duration = 1 } } }
  end }
  local png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/AAAZ4gk3AAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="
  terminal:write("\27_Ga=t,t=d,f=100,s=1,v=1,i=1;" .. png .. "\27\\\27_Ga=p,i=1,p=1,c=1,r=1,C=1\27\\")
end

local function resource()
  return { destroyed = 0, cell_width = 8, cell_height = 16,
    destroy = function(self) self.destroyed = self.destroyed + 1 end,
    invalidate = function() end }
end

local function setup()
  local sessions, created = {}, {}
  local workspace = Workspace.new()
  for index = 1, 3 do
    local session = { terminal = Terminal.new({ columns = 8, rows = 3 }), renderer = resource(), metrics = {},
      pty = { resizes = 0, resize = function(self, columns, rows)
        self.resizes = self.resizes + 1; self.columns, self.rows = columns, rows
      end } }
    session.terminal:write("persist\r\n\27[4:3m界é\27[0m\27[?2031h")
    session.terminal:pop_effects()
    sessions[index] = session
    if index == 1 then workspace:new_tab(session) else workspace:split("vertical", session) end
  end
  local options = {
    current = Config.parse("font-size = 16\nbackground = #000000"),
    candidate = Config.parse("font-size = 18\nbackground = #ffffff\nosc52-write = true"),
    workspace = workspace, font = resource(),
    dimensions = function() return 30, 4 end,
    new_font = function() local value = resource(); created.font = value; return value end,
    new_renderer = function(_, state)
      local value = resource(); value.state = state; created[#created + 1] = value
      -- A constructor may consume damage without affecting the live renderer.
      state.damage:clear(); state.text_damage:clear()
      return value
    end,
  }
  for _, session in ipairs(sessions) do session.metrics.font = options.font end
  return options, sessions, created
end

return {
  palette_staging_copies_only_accessed_history_and_retains_selection = function()
    local terminal = Terminal.new({ columns = 8, rows = 2, state_options = { scrollback_limit = 32 } })
    for line = 1, 48 do terminal:write(string.format("%04d界\r\n", line)) end
    local state = Terminal.state(terminal)
    state:scroll_history(8)
    state:set_selection(0, 1, 1, 6)
    local before = Snapshot.encode(state)
    local transaction = StateTransaction.new(state)
    local candidate = transaction.state
    candidate:configure_palette(Config.parse("background = #ffffff"))
    local view = candidate:selection_view()
    Assert.truthy(view.active)
    Assert.equal(view.start.line_id, state:selection_view().start.line_id)
    -- Selection uses line identities and cluster widths, not cached colours.
    for index = 1, state.scrollback:size() do
      Assert.equal(candidate.scrollback:peek(index), state.scrollback:peek(index))
    end
    local visible = candidate:visible_row(0)
    Assert.equal(visible.cells[0].bg, candidate.colors.background)
    Assert.truthy(visible ~= state:visible_row(0))
    Assert.equal(Snapshot.encode(state), before)
    local copied = 0
    for index = 1, state.scrollback:size() do
      if candidate.scrollback:peek(index) ~= state.scrollback:peek(index) then copied = copied + 1 end
    end
    Assert.equal(copied, 1)
    transaction:seal(); transaction:commit(); transaction:publish_effects()
    Assert.equal(state.scrollback.borrowed, nil)
    Assert.equal(state.scrollback:get(1).cells[0].bg, state.colors.background)
    terminal:write("\27]11;#123456\7")
    Assert.equal(state.scrollback:get(1).cells[0].bg, state.colors.background)
  end,
  palette_staging_abort_and_history_eviction_do_not_mutate_borrowed_rows = function()
    local terminal = Terminal.new({ columns = 8, rows = 2, state_options = { scrollback_limit = 4 } })
    for line = 1, 12 do terminal:write(string.format("%04d\r\n", line)) end
    local state = Terminal.state(terminal)
    local first = state.scrollback:get(1)
    local before, first_text = Snapshot.encode(state), first.cells[0].glyph
    local transaction = StateTransaction.new(state)
    transaction.state:configure_palette(Config.parse("background = #ffffff"))
    for line = 1, 8 do transaction.state:write_codepoint("X"); transaction.state:line_feed() end
    Assert.equal(Snapshot.encode(state), before)
    Assert.equal(state.scrollback:get(1), first)
    Assert.equal(first.cells[0].glyph, first_text)
    transaction.state.scrollback:clear()
    Assert.equal(state.scrollback:size(), 4)
  end,
  direct_reflow_with_pending_history_colours_keeps_original_cache_untouched = function()
    local terminal = Terminal.new({ columns = 8, rows = 2 })
    terminal:write("history\r\nsecond\r\nthird")
    local state = Terminal.state(terminal)
    local original_row = state.scrollback:peek(1)
    local original_background = original_row.cells[0].bg
    state:configure_palette(Config.parse("background = #ffffff"))
    Assert.equal(original_row.cells[0].bg, original_background)
    local staged = StateTransaction.new(state, { columns = 4, rows = 3 })
    Assert.equal(original_row.cells[0].bg, original_background)
    Assert.equal(staged.state.scrollback:get(1).cells[0].bg, state.colors.background)
    staged.state.scrollback:get(1).cells[0].glyph = "X"
    Assert.equal(original_row.cells[0].glyph, "h")
  end,
  state_transaction_preserves_all_cell_renditions_and_independent_blank_storage = function()
    local terminal = Terminal.new({ columns = 8, rows = 2 })
    terminal:write("\27]8;;https://example.com\7\27[1;2;3;4:3;7;8;9;58:2::1:2:3m界é\27]8;;\7\27[0m")
    local state = Terminal.state(terminal)
    local transaction = StateTransaction.new(state)
    Assert.equal(Snapshot.encode(transaction.state), Snapshot.encode(state))
    for row = 0, state.rows - 1 do
      for column = 0, state.columns - 1 do
        local source, candidate = state:get(column, row), transaction.state:get(column, row)
        Assert.truthy(source ~= candidate)
        for key, value in pairs(source) do Assert.equal(candidate[key], value) end
      end
    end
    transaction.state:get(7, 1).fg = 123
    Assert.truthy(state:get(7, 1).fg ~= 123)
  end,
  direct_reflow_failure_leaves_original_image_anchors_and_line_ids_unchanged = function()
    local terminal = Terminal.new({ columns = 8, rows = 2 })
    terminal:write("source\r\nhistory\r\nend")
    upload_image(terminal)
    local state = Terminal.state(terminal)
    local before, line_id = Snapshot.encode(state), state.next_line_id
    local transform = state.reflow.transform
    state.reflow.transform = function() error("injected reflow failure") end
    local ok = pcall(StateTransaction.new, state, { columns = 4, rows = 3 })
    state.reflow.transform = transform
    Assert.equal(ok, false)
    Assert.equal(Snapshot.encode(state), before)
    Assert.equal(state.next_line_id, line_id)
    Assert.truthy(#state.kitty_placements.placements > 0)
  end,
  direct_reflow_staging_matches_full_clone_and_keeps_source_cells_private = function()
    for _, size in ipairs({ {4, 3}, {8, 4}, {10, 2}, {1, 3} }) do
      local terminal = Terminal.new({ columns = 8, rows = 2 })
      terminal:write("\27[4:3;58:5:1mA界é\r\nsecond\r\nthird\r\nfourth\27[0m")
      upload_image(terminal)
      terminal:write("\27[?1049hALT")
      local state = Terminal.state(terminal)
      local before = Snapshot.encode(state)
      local original_history_color = state.scrollback:get(1).cells[0].bg
      local expected = StateTransaction.new(state)
      expected.state:resize(size[1], size[2])
      local staged = StateTransaction.new(state, { columns = size[1], rows = size[2] })
      Assert.equal(Snapshot.encode(staged.state), Snapshot.encode(expected.state))
      Assert.equal(staged.state.scrollback:size(), expected.state.scrollback:size())
      for index = 1, staged.state.scrollback:size() do
        local a, b = staged.state.scrollback:get(index), expected.state.scrollback:get(index)
        for column = 0, size[1] - 1 do
          Assert.equal(a.cells[column].glyph, b.cells[column].glyph)
          Assert.equal(a.cells[column].underline_style, b.cells[column].underline_style)
        end
      end
      staged.state:configure_palette(Config.parse("background = #ffffff"))
      Assert.equal(Snapshot.encode(state), before)
      Assert.equal(state.scrollback:get(1).cells[0].bg, original_history_color)
      staged:seal(); staged:commit(); staged:publish_effects()
      terminal:write("\27[?1049l\27[HOK")
      Assert.equal(state.cells[0].glyph, "O")
    end
  end,
  state_transaction_shares_immutable_clusters_but_isolates_grapheme_extension = function()
    local terminal = Terminal.new({ columns = 8, rows = 2 })
    terminal:write("A界e")
    local state = Terminal.state(terminal)
    local transaction = StateTransaction.new(state)
    Assert.equal(transaction.state:get(0, 0).codepoints, state:get(0, 0).codepoints)
    Assert.equal(transaction.state:get(1, 0).codepoints, state:get(1, 0).codepoints)
    transaction.state:write_codepoint("́", 0x301)
    Assert.equal(transaction.state:get(3, 0).glyph, "é")
    Assert.equal(state:get(3, 0).glyph, "e")
    Assert.equal(#state:get(3, 0).codepoints, 1)
    transaction:seal(); transaction:commit(); transaction:publish_effects()
    terminal:write("̂")
    Assert.equal(state:get(3, 0).glyph, "é̂")
  end,
  reload_resource_failures_leave_all_panes_and_effects_untouched = function()
    for fail_at = 1, 3 do
      local options, sessions, created = setup()
      local snapshots, renderers, lines = {}, {}, {}
      for index, session in ipairs(sessions) do
        snapshots[index] = Snapshot.encode(Terminal.state(session.terminal))
        renderers[index] = session.renderer
        lines[index] = Terminal.state(session.terminal).next_line_id
      end
      local create, calls = options.new_renderer, 0
      options.new_renderer = function(...)
        calls = calls + 1
        if calls == fail_at then error("injected GPU allocation failure") end
        return create(...)
      end
      local plan, reason = Reload.prepare(options)
      Assert.equal(plan, nil)
      Assert.truthy(reason:find("injected GPU allocation failure", 1, true))
      Assert.equal(created.font.destroyed, 1)
      Assert.equal(options.font.destroyed, 0)
      for _, renderer in ipairs(created) do Assert.equal(renderer.destroyed, 1) end
      for index, session in ipairs(sessions) do
        Assert.equal(Snapshot.encode(Terminal.state(session.terminal)), snapshots[index])
        Assert.equal(Terminal.state(session.terminal).next_line_id, lines[index])
        Assert.equal(session.renderer, renderers[index])
        Assert.equal(session.renderer.destroyed, 0)
        Assert.equal(session.pty.resizes, 0)
        Assert.equal(#session.terminal:pop_effects(), 0)
        Assert.equal(#session.terminal:pop_responses(), 0)
        session.terminal:write("\rOK")
        Assert.equal(Terminal.state(session.terminal):get(0, 1).glyph, "O")
      end
    end
  end,
  reload_font_and_geometry_failure_never_destroy_the_original_font = function()
    local options, _, created = setup()
    options.new_font = function() error("font allocation failed") end
    Assert.equal(Reload.prepare(options), nil)
    Assert.equal(options.font.destroyed, 0)
    options.new_font = function() local value = resource(); created.font = value; return value end
    options.dimensions = function() return 1, 1 end
    Assert.equal(Reload.prepare(options), nil)
    Assert.equal(created.font.destroyed, 1)
    Assert.equal(options.font.destroyed, 0)
    options.candidate.scrollback_limit = options.current.scrollback_limit + 1
    local plan, reason = Reload.prepare(options)
    Assert.equal(plan, nil)
    Assert.truthy(reason:find("new terminal session", 1, true))
  end,
  reload_abort_is_idempotent_and_preserves_a_reused_font = function()
    local options, sessions, created = setup()
    options.candidate.font_size = options.current.font_size
    local plan = assert(Reload.prepare(options))
    Assert.equal(plan.font, options.font)
    Assert.equal(#plan:abort(), 0)
    Assert.equal(#plan:abort(), 0)
    Assert.equal(options.font.destroyed, 0)
    for _, renderer in ipairs(created) do Assert.equal(renderer.destroyed, 1) end
    for _, session in ipairs(sessions) do Assert.equal(session.renderer.destroyed, 0) end
  end,
  reload_commits_all_panes_before_effects_or_child_resize = function()
    local options, sessions, created = setup()
    local states, parsers, old_renderers = {}, {}, {}
    for index, session in ipairs(sessions) do
      states[index] = Terminal.state(session.terminal)
      parsers[index] = Terminal.parser(session.terminal)
      old_renderers[index] = session.renderer
      session.terminal.effect_handlers.any = function()
        for _, other in ipairs(sessions) do Assert.equal(Terminal.state(other.terminal).osc52_write, true) end
      end
    end
    -- Preserve an incomplete UTF-8 sequence across state adoption.
    sessions[1].terminal:write("\r\231")
    local plan = assert(Reload.prepare(options))
    for _, session in ipairs(sessions) do Assert.equal(Terminal.state(session.terminal).osc52_write, false) end
    plan:activate()
    for index, session in ipairs(sessions) do
      Assert.equal(Terminal.state(session.terminal), states[index])
      Assert.equal(Terminal.parser(session.terminal), parsers[index])
      Assert.equal(session.renderer, created[index])
      Assert.equal(session.metrics.font, created.font)
      Assert.equal(session.pty.resizes, 0)
      Assert.equal(old_renderers[index].destroyed, 0)
      Assert.equal(#session.terminal:pop_responses(), 0)
    end
    Assert.equal(pcall(function() plan:abort() end), false)
    Assert.equal(#plan:finish(), 0)
    for index, session in ipairs(sessions) do
      Assert.equal(old_renderers[index].destroyed, 1)
      Assert.equal(#session.terminal:diagnostics().effect_errors, 0)
      Assert.equal(session.terminal:pop_responses()[1], "\27[?997;2n")
      Assert.equal(session.pty.resizes, 1)
      Assert.equal(Terminal.state(session.terminal).rows, session.pty.rows)
    end
    Assert.equal(options.font.destroyed, 1)
    sessions[1].terminal:write("\149\140")
    Assert.equal(states[1]:get(0, 1).glyph, "界")
    -- Fresh row factories and cell projection must refer to the adopted state.
    sessions[1].terminal:write("\27[999;1H\r\nAFTER")
    Assert.equal(states[1].cells[states[1]:index(0, states[1].rows - 1)].glyph, "A")
    Assert.equal(states[1].primary.blank_cell(states[1]).bg, options.candidate.background)
  end,
  reload_contains_cleanup_and_pty_errors_after_a_successful_commit = function()
    local options, sessions = setup()
    sessions[1].renderer.destroy = function() error("old renderer cleanup") end
    sessions[2].pty.resize = function() error("closed PTY") end
    local plan = assert(Reload.prepare(options))
    plan:activate()
    local errors = plan:finish()
    Assert.equal(#errors, 2)
    Assert.equal(options.font.destroyed, 1)
    Assert.equal(sessions[3].pty.resizes, 1)
    for _, session in ipairs(sessions) do
      Assert.equal(session.renderer.destroyed, 0)
      session.terminal:write("\rnext")
    end
  end,
  reload_stages_hidden_and_zoomed_panes_without_resizing_their_children = function()
    local options, sessions = setup()
    options.workspace:toggle_zoom()
    local active = options.workspace:active_pane().session
    local plan = assert(Reload.prepare(options))
    plan:activate(); plan:finish()
    for _, session in ipairs(sessions) do
      Assert.equal(Terminal.state(session.terminal).osc52_write, true)
      Assert.equal(session.pty.resizes, session == active and 1 or 0)
    end
  end,
  state_transaction_isolates_history_images_and_bound_callbacks = function()
    local terminal = Terminal.new({ columns = 8, rows = 2 })
    terminal:write("history\r\nsecond\r\nthird")
    upload_image(terminal)
    local state = Terminal.state(terminal)
    Assert.truthy(state.kitty_graphics:has_image(1))
    Assert.truthy(state.kitty_graphics:register_gpu_upload(1, state.kitty_graphics.images[1].generation, 4))
    local before, line_id = Snapshot.encode(state), state.next_line_id
    local transaction = StateTransaction.new(state)
    transaction.state.kitty_graphics:delete_image(1)
    transaction.state:resize(4, 3)
    transaction.state:configure_palette(Config.parse("background = #ffffff"))
    Assert.equal(Snapshot.encode(state), before)
    Assert.equal(state.next_line_id, line_id)
    Assert.equal(state.kitty_graphics.images[1].gpu_bytes, 4)
    Assert.equal(state.scrollback:get(1).cells[0].glyph, "h")
    transaction:seal(); transaction:commit(); transaction:publish_effects()
    Assert.equal(state.kitty_graphics:has_image(1), false)
    terminal:write("\27[?1049hALT\27[?1049l\27[2J\27[HOK")
    Assert.equal(state.cells[0].glyph, "O")
    Assert.equal(state.cells[1].glyph, "K")
  end,
  reload_replacement_images_do_not_inherit_old_texture_residency = function()
    local options, sessions = setup()
    upload_image(sessions[1].terminal)
    local graphics = Terminal.state(sessions[1].terminal).kitty_graphics
    local generation = graphics.images[1].generation
    Assert.truthy(graphics:register_gpu_upload(1, generation, 4))
    local create = options.new_renderer
    options.new_renderer = function(font, state, render_options)
      if state.kitty_graphics:has_image(1) then
        Assert.equal(state.kitty_graphics.images[1].gpu_bytes, 0)
        Assert.truthy(state.kitty_graphics:register_gpu_upload(1, generation, 4))
      end
      return create(font, state, render_options)
    end
    local plan = assert(Reload.prepare(options))
    Assert.equal(graphics.images[1].gpu_bytes, 4)
    plan:activate(); plan:finish()
    Assert.equal(Terminal.state(sessions[1].terminal).kitty_graphics.images[1].gpu_bytes, 4)
    Assert.truthy(Terminal.state(sessions[1].terminal).kitty_graphics ~= graphics)
  end,
}
