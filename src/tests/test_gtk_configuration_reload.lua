local Assert = require("tests.assert")
local Config = require("kiwi.config")
local Reload = require("kiwi.app.gtk_configuration_reload")
local Snapshot = require("kiwi.terminal.snapshot")
local Terminal = require("kiwi.session.terminal")

local function resource()
  return { cell_width = 8, cell_height = 16, revision = 37, destroyed = 0,
    destroy = function(self) self.destroyed = self.destroyed + 1 end,
    invalidate = function(self, reason) self.invalidated = reason end }
end

local function setup()
  local created, sessions = {}, {}
  local current = Config.parse("font-size = 16\nbackground = #000000")
  for index = 1, 2 do
    local terminal = Terminal.new({ columns = 8, rows = 3 })
    for _ = 1, 8 do terminal:write("keep界\r\n") end
    terminal:write("\27[?2031h")
    terminal:pop_effects()
    sessions[index] = { terminal = terminal, state = Terminal.state(terminal), window = { resized = true },
      font = resource(), consumer = resource(), configuration = current,
      pty = { resizes = 0, resize = function(self) self.resizes = self.resizes + 1 end } }
  end
  return {
    current = current, candidate = Config.parse("font-size = 18\nbackground = #ffffff"), sessions = sessions,
    dimensions = function() return 12, 4 end,
    new_font = function() local font = resource(); created[#created + 1] = font; return font end,
    new_consumer = function(_, _, state, _, revision)
      Assert.equal(revision, 37)
      local consumer = resource(); created[#created + 1] = consumer
      state.damage:clear(); state.text_damage:clear()
      return consumer
    end,
  }, sessions, created
end

return {
  gtk_reload_stages_all_pages_and_preserves_live_state_until_activation = function()
    local options, sessions = setup()
    local states, before, fonts, consumers = {}, {}, {}, {}
    for i, session in ipairs(sessions) do
      states[i], before[i] = session.state, Snapshot.encode(session.state)
      fonts[i], consumers[i] = session.font, session.consumer
    end
    local plan = assert(Reload.prepare(options))
    for i, session in ipairs(sessions) do
      Assert.equal(Snapshot.encode(session.state), before[i])
      Assert.equal(session.font, fonts[i])
      Assert.equal(session.consumer, consumers[i])
      Assert.equal(session.pty.resizes, 0)
    end
    plan:activate()
    for i, session in ipairs(sessions) do
      Assert.equal(Terminal.state(session.terminal), states[i])
      Assert.equal(session.state.colors.background, options.candidate.background)
      Assert.equal(session.configuration, options.candidate)
      Assert.equal(session.state.columns, 12)
      Assert.equal(session.state.rows, 4)
      Assert.equal(session.consumer.invalidated, "configuration")
      Assert.truthy(session.state.scrollback:size() > 0)
      Assert.equal(consumers[i].destroyed, 0)
      Assert.equal(session.pty.resizes, 0)
    end
    Assert.equal(#plan:finish(), 0)
    for i, session in ipairs(sessions) do
      Assert.equal(session.pty.resizes, 1)
      Assert.equal(fonts[i].destroyed, 1)
      Assert.equal(consumers[i].destroyed, 1)
      session.terminal:write("still-live")
      Assert.equal(session.state:get(0, session.state.cursor.row).glyph, "s")
    end
    Assert.equal(pcall(plan.activate, plan), false)
    Assert.equal(pcall(plan.finish, plan), false)
  end,
  gtk_reload_releases_staged_pages_when_a_later_constructor_fails = function()
    for failure = 1, 4 do
      local options, sessions, created = setup()
      local before = { Snapshot.encode(sessions[1].state), Snapshot.encode(sessions[2].state) }
      local count, font, consumer = 0, options.new_font, options.new_consumer
      local function fail_at(callback, ...)
        count = count + 1
        if count == failure then error("injected page resource failure") end
        return callback(...)
      end
      options.new_font = function(...) return fail_at(font, ...) end
      options.new_consumer = function(...) return fail_at(consumer, ...) end
      local plan, reason = Reload.prepare(options)
      Assert.equal(plan, nil)
      Assert.truthy(reason:find("injected page resource failure", 1, true))
      for _, value in ipairs(created) do Assert.equal(value.destroyed, 1) end
      for index, session in ipairs(sessions) do
        Assert.equal(Snapshot.encode(session.state), before[index])
        Assert.equal(session.configuration, options.current)
        Assert.equal(session.font.destroyed, 0)
        Assert.equal(session.consumer.destroyed, 0)
        Assert.equal(session.pty.resizes, 0)
      end
    end
  end,
  gtk_reload_abort_keeps_shared_fonts_and_hidden_page_geometry = function()
    local options, sessions, created = setup()
    options.candidate = Config.parse("font-size = 16\nbackground = #ffffff")
    options.dimensions = function() return nil end
    options.new_font = function() error("unchanged font must be retained") end
    local plan = assert(Reload.prepare(options))
    Assert.equal(plan.entries[1].columns, 8)
    Assert.equal(plan.entries[1].rows, 3)
    Assert.equal(#plan:abort(), 0)
    Assert.equal(#plan:abort(), 0)
    for _, value in ipairs(created) do Assert.equal(value.destroyed, 1) end
    for _, session in ipairs(sessions) do
      Assert.equal(session.font.destroyed, 0)
      Assert.equal(session.consumer.destroyed, 0)
      Assert.equal(session.window.resized, true)
    end
  end,
  gtk_reload_rejects_unsupported_changes_before_allocating_resources = function()
    for _, setting in ipairs({ "background-opacity = 0.5", "scrollback-limit = 17", "ambiguous-width = 2" }) do
      local options, _, created = setup()
      options.candidate = Config.parse(setting)
      local plan, reason = Reload.prepare(options)
      Assert.equal(plan, nil)
      Assert.truthy(type(reason) == "string")
      Assert.equal(#created, 0)
    end
  end,
}
