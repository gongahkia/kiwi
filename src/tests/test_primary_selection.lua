local Assert = require("tests.assert")
local Terminal = require("kiwi.session.terminal")
local Primary = require("kiwi.input.primary_selection")
local Pointer = require("kiwi.input.selection_pointer")
local Config = require("kiwi.config")
local Interaction = require("kiwi.app.interaction_actions")
local function fixture()
  local terminal = Terminal.new({ columns = 12, rows = 2 })
  terminal:write("a中b hello")
  local state, writes, requests = Terminal.state(terminal), {}, {}
  local bridge = { primary_supported = function() return true end,
    primary_write = function(_, text) writes[#writes + 1] = text; return true end,
    clipboard_write = function() error("PRIMARY overwrote CLIPBOARD") end,
    clipboard_read = function() error("PRIMARY read CLIPBOARD") end }
  function bridge:primary_read()
    local request = { polls = 0, closed = false, text = "paste", status = "success" }
    function request:poll()
      self.polls = self.polls + 1
      if self.polls == 1 then return nil, "pending" end
      return self.text, self.status
    end
    function request:destroy() self.closed = true end
    requests[#requests + 1] = request
    return request, "pending"
  end
  return Primary.new(bridge), state, writes, requests, terminal
end
local function middle(action, modifiers) return { kind = "button", button = 2, action = action or "press", modifiers = modifiers or 0 } end
return {
  primary_keyboard_paste_targets_find_and_cancels_if_its_query_changes = function()
    local primary, state, _, requests = fixture()
    state:vi_toggle(); state:search_begin()
    Assert.truthy(primary:paste(state, true))
    primary:poll(state, true)
    local bytes, status, changed = primary:poll(state, true)
    Assert.equal(bytes, nil); Assert.equal(status, "query"); Assert.truthy(changed)
    Assert.equal(state.search.query, "paste")
    primary:paste(state, true)
    state:search_append("x")
    primary:poll(state, true); primary:poll(state, true)
    Assert.equal(state.search.query, "pastex")
    Assert.truthy(requests[2].closed)
    state.search.query = string.rep("x", state.search.maximum_query_bytes - 1)
    primary:paste(state, true)
    Assert.equal(primary.read_limit, 1)
    primary:poll(state, true); primary:poll(state, true)
    Assert.equal(#state.search.query, state.search.maximum_query_bytes - 1)
    Assert.equal(primary.status, "over-limit")
    state.search.query = state.search.query .. "x"
    Assert.equal(primary:paste(state, true), false)
    Assert.equal(#requests, 3)
  end,
  primary_product_actions_publish_vi_text_and_request_paste_without_immediate_pty_input = function()
    local primary, state, writes, requests = fixture()
    local function enqueue() error("primary action bypassed asynchronous delivery") end
    state:vi_toggle(); state.vi:toggle_selection(state, "character")
    Assert.truthy(Interaction.terminal("copy-primary", state, nil, enqueue, primary, true))
    Assert.equal(#writes, 1)
    Assert.equal(Interaction.terminal("paste-primary", state, nil, enqueue, primary, true), nil)
    Assert.equal(#requests, 0)
    state:vi_toggle()
    Assert.truthy(Interaction.terminal("paste-primary", state, nil, enqueue, primary, true))
    Assert.equal(primary:poll(state, true), nil)
    Assert.equal(primary:poll(state, true), "paste")
    Assert.equal(Interaction.terminal("paste-primary", state, nil, enqueue, primary, false), nil)
    Assert.equal(Interaction.terminal("copy-primary", state, nil, enqueue), nil)
  end,
  primary_auto_publication_tracks_only_completed_fresh_vi_selections = function()
    local primary, state, writes, _, terminal = fixture()
    primary:focus(state)
    state:vi_toggle(); state.vi:toggle_selection(state, "character")
    primary:sync_keyboard(state, true)
    Assert.equal(#writes, 1)
    primary:sync_keyboard(state, true); Assert.equal(#writes, 1)
    state.vi:motion(state, "left")
    terminal:write("output")
    primary:sync_keyboard(state, true); Assert.equal(#writes, 1)
    state.vi:motion(state, "left")
    primary:focus(state) -- Focusing an existing selection must not reclaim PRIMARY.
    primary:sync_keyboard(state, true); Assert.equal(#writes, 1)
    state.vi:motion(state, "left")
    primary:sync_keyboard(state, false); Assert.equal(#writes, 1)
    primary:sync_keyboard(state, true); Assert.equal(#writes, 1)
    state.vi:motion(state, "left")
    primary:sync_keyboard(state, true); Assert.equal(#writes, 2)
  end,
  primary_auto_publication_waits_for_bounded_word_expansion = function()
    local terminal = Terminal.new({ columns = 100, rows = 40 })
    terminal:write(string.rep("x", 3500))
    local state, writes = Terminal.state(terminal), {}
    local primary = Primary.new({ primary_supported = function() return true end,
      primary_write = function(_, text) writes[#writes + 1] = text; return true end })
    primary:focus(state)
    state:vi_toggle(); state.vi:motion(state, "top"); state.vi:toggle_selection(state, "word")
    Assert.truthy(state:vi_pending())
    primary:sync_keyboard(state, true); Assert.equal(#writes, 0)
    while state:vi_pending() do state:vi_step(31); primary:sync_keyboard(state, true) end
    Assert.equal(#writes, 1); Assert.equal(#writes[1], 3500)
  end,
  primary_repeated_clicks_keep_one_conversion_and_only_the_latest_target = function()
    local primary, state, _, requests = fixture()
    for _ = 1, 100 do primary:button(middle(), state, true) end
    Assert.equal(#requests, 1)
    Assert.equal(primary:poll(state, true), nil)
    Assert.equal(primary:poll(state, true), nil)
    Assert.equal(#requests, 2)
    Assert.equal(primary:poll(state, true), nil)
    Assert.equal(primary:poll(state, true), "paste")
    primary:button(middle(), state, true)
    state.modes.mouse_tracking = "normal"
    -- A fresh application-owned press replaces a lost local release claim.
    Assert.equal(primary:button(middle(), state, true), false)
    Assert.equal(primary:button(middle("release"), state, true), false)
    primary:destroy()
  end,
  primary_selection_publishes_completed_pointer_selection_without_clipboard_sync = function()
    local primary, state, writes = fixture()
    local pointer = Pointer.new()
    local function event(action, column)
      local value = { kind = "button", button = 0, action = action, selection_row = 0, selection_column = column,
        x = column * 10, y = 0, time = action == "press" and 1 or 1.1 }
      local handled = pointer:handle(value, state, {})
      primary:selection(value, state, handled, true)
    end
    event("press", 0); Assert.equal(#writes, 0)
    pointer:handle({ kind = "motion", selection_row = 0, selection_column = 2 }, state, {})
    Assert.equal(#writes, 0)
    event("release", 2); Assert.equal(writes[1], "a中")
    primary:selection({ kind = "button", button = 0, action = "release" }, state, true, true)
    Assert.equal(#writes, 1)
    state:set_selection(0, 0, 0, 0)
    Assert.equal(primary:publish(state), false); Assert.equal(#writes, 1)
    primary.maximum_bytes = 2; state:set_selection(0, 0, 0, 3)
    Assert.equal(primary:publish(state), false); Assert.equal(#writes, 1)
    Assert.equal(primary:publish(state, false), false)
  end,
  primary_paste_is_async_bracketed_and_owns_the_matching_release = function()
    local primary, state, _, requests = fixture()
    state.modes.bracketed_paste = true
    Assert.truthy(primary:button(middle(), state, true))
    Assert.equal(primary:poll(state, true), nil)
    Assert.equal(primary:poll(state, true), "\27[200~paste\27[201~")
    Assert.truthy(requests[1].closed)
    Assert.equal(primary:poll(state, true), nil)
    state.modes.mouse_tracking = "normal"
    Assert.truthy(primary:button(middle("release"), state, true))
    Assert.equal(primary:button(middle("release"), state, true), false)
  end,
  primary_middle_click_respects_application_mouse_and_shift_capture_policy = function()
    for _, tracking in ipairs({ "x10", "normal", "button", "any" }) do
      local primary, state, _, requests = fixture()
      state.modes.mouse_tracking = tracking
      Assert.equal(primary:button(middle(), state, true), false)
      Assert.equal(#requests, 0)
      Assert.truthy(primary:button(middle("press", 1), state, true))
      primary:cancel()
      state.modes.mouse_shift_escape = true
      Assert.equal(primary:button(middle("press", 1), state, true), false)
      Assert.truthy(primary:button(middle("press", 1), state, true, "never"))
      primary:cancel()
      Assert.equal(primary:button(middle("press", 1), state, true, "always"), false)
    end
  end,
  primary_pending_paste_is_cancelled_on_target_policy_and_input_mode_changes = function()
    for _, kind in ipairs({ "pane", "disabled", "screen", "bracket", "vi", "hints", "search", "blur" }) do
      local primary, state, _, requests, terminal = fixture()
      primary:button(middle(), state, true)
      local enabled = true
      if kind == "pane" then state = Terminal.state(Terminal.new({ columns = 12, rows = 2 }))
      elseif kind == "disabled" then enabled = false
      elseif kind == "screen" then terminal:write("\27[?1049h")
      elseif kind == "bracket" then state.modes.bracketed_paste = not state.modes.bracketed_paste
      elseif kind == "vi" then state:vi_toggle()
      elseif kind == "hints" then state:hints_begin()
      elseif kind == "search" then state:search_begin()
      else primary:cancel() end
      Assert.equal(primary:poll(state, enabled), nil)
      Assert.equal(primary:poll(state, enabled), nil)
      Assert.truthy(requests[1].closed)
      Assert.equal(primary.request, nil)
    end
  end,
  primary_paste_rejects_bad_utf8_nuls_limits_and_failed_transfers = function()
    for _, value in ipairs({ "\255", "a\0b", string.rep("a", 17), "" }) do
      local primary, state, _, requests = fixture()
      primary.maximum_bytes = 16
      primary:button(middle(), state, true)
      requests[1].text = value
      primary:poll(state, true)
      Assert.equal(primary:poll(state, true), nil)
      Assert.truthy(requests[1].closed)
    end
    local primary, state, _, requests = fixture()
    primary:button(middle(), state, true)
    requests[1].text, requests[1].status = nil, "timeout"
    primary:poll(state, true)
    Assert.equal(primary:poll(state, true), nil)
    Assert.equal(primary.status, "timeout")
  end,
  primary_restart_and_unsupported_hosts_release_resources_without_reading_clipboard = function()
    local primary, state, _, requests = fixture()
    primary:button(middle(), state, true)
    primary:button(middle(), state, true)
    Assert.equal(#requests, 1)
    primary:poll(state, true); primary:poll(state, true)
    Assert.truthy(requests[1].closed); Assert.equal(#requests, 2)
    primary:destroy(); Assert.truthy(requests[2].closed)
    primary.bridge.primary_supported = nil
    Assert.equal(primary:button(middle(), state, true), false)
    Assert.equal(primary:publish(state, true), false)
  end,
  primary_configuration_is_explicit_and_boolean = function()
    Assert.equal(Config.parse("primary-selection = false").primary_selection, false)
    Assert.equal(Config.parse("primary-selection = true").primary_selection, true)
    Assert.equal(Config.parse("").primary_selection, true)
    Assert.equal(pcall(Config.parse, "primary-selection = maybe"), false)
    local configured = Config.apply_environment(Config.parse(""), function(name)
      if name == "KIWI_PRIMARY_SELECTION" then return "false" end
    end)
    Assert.equal(configured.primary_selection, false)
    Assert.equal(Config.equivalent(configured, Config.parse("")), false)
  end,
}
