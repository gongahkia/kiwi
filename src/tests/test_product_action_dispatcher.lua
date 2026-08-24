local Assert = require("tests.assert")
local Dispatcher = require("kiwi.app.product_action_dispatcher")

local function dispatcher(options)
  options = options or {}
  local state = {
    configuration = { command_palette_entries = {} },
    configuration_path = options.configuration_path,
    created_splits = {},
    logs = {},
    opened_paths = {},
    session = {},
  }
  local application = {
    mark_layout_dirty = function() state.layout_marks = (state.layout_marks or 0) + 1 end,
    move_active_to_new_window = function(_, identifier)
      state.move_new_identifier = identifier
      return options.move_new ~= false, options.move_new_reason
    end,
    move_active_to_next_window = function(_, identifier)
      state.move_next_identifier = identifier
      return options.move_next ~= false, options.move_next_reason
    end,
    move_active_to_window = function(_, source_identifier, target_identifier)
      state.move_selected_source_identifier = source_identifier
      state.move_selected_target_identifier = target_identifier
      return options.move_selected ~= false, options.move_selected_reason
    end,
    duplicate_active_to_next_window = function()
      state.duplicate_next = true
      return options.duplicate_next ~= false, options.duplicate_next_reason
    end,
    duplicate_active_to_window = function(_, source_identifier, target_identifier)
      state.duplicate_selected_source_identifier = source_identifier
      state.duplicate_selected_target_identifier = target_identifier
      return options.duplicate_selected ~= false, options.duplicate_selected_reason
    end,
    request_window = function(_, path, request)
      state.requested_path = path
      state.window_request = request
      return options.request_window ~= false, options.request_window_reason
    end,
    session_targets = function(_, identifier)
      state.target_source_identifier = identifier
      return options.targets or { { id = 18, title = "Window 18" } }, options.targets_reason
    end,
  }
  local host = {
    platform = "Linux",
    open_text_file = function(_, path)
      state.opened_paths[#state.opened_paths + 1] = path
      return options.open_text_file ~= false, options.open_text_file_reason
    end,
  }
  if options.palette then
    host.show_command_palette = function(_, entries, callback)
      state.palette_entries = entries
      callback(options.palette)
      return true
    end
  end
  local value = Dispatcher.new({
    active_session = function() return state.session end,
    application = application,
    close_active_pane = function()
      state.closed = true
      return options.close ~= false, options.close_reason
    end,
    configuration = function() return state.configuration end,
    configuration_path = function() return state.configuration_path end,
    controller_id = 17,
    create_split = function(direction)
      state.created_splits[#state.created_splits + 1] = direction
      return options.split ~= false, options.split_reason
    end,
    create_tab = function()
      state.created_tabs = (state.created_tabs or 0) + 1
      return options.tab ~= false, options.tab_reason
    end,
    ensure_configuration_file = function(path, contents)
      state.initialization_count = (state.initialization_count or 0) + 1
      state.initialized_path = path
      state.initialized_contents = contents
      return options.initialize ~= false, options.initialize_reason
    end,
    explicit_configuration_path = options.explicit_configuration_path,
    focus_next_tab = function()
      state.focused_next = (state.focused_next or 0) + 1
      return options.focus ~= false
    end,
    host = host,
    initial_working_directory = function() return options.initial_working_directory end,
    report = function(message) state.logs[#state.logs + 1] = message end,
    request_configuration_reload = function() state.reload_requested = true end,
    session_move_smoke_requester = options.session_move_smoke_requester,
    set_configuration_path = function(path)
      state.configuration_path = path
      state.configuration.path = path
    end,
    window = {},
  })
  return value, state
end

return {
  product_action_dispatcher_routes_workspace_and_window_intents = function()
    local actions, state = dispatcher({ initial_working_directory = "/tmp/kiwi work" })
    local handled, layout_changed = actions:handle("new-tab")
    Assert.truthy(handled and layout_changed)
    Assert.equal(state.created_tabs, 1)
    handled, layout_changed = actions:handle("split-right")
    Assert.truthy(handled and layout_changed)
    handled, layout_changed = actions:handle("split-down")
    Assert.truthy(handled and layout_changed)
    Assert.equal(table.concat(state.created_splits, ","), "vertical,horizontal")
    handled, layout_changed = actions:handle("next-tab")
    Assert.truthy(handled and layout_changed)
    handled, layout_changed = actions:handle("close-pane")
    Assert.truthy(handled and layout_changed)
    handled, layout_changed = actions:handle("new-window")
    Assert.truthy(handled and not layout_changed)
    Assert.equal(state.requested_path, nil)
    Assert.equal(state.window_request.kind, "standalone")
    Assert.equal(state.window_request.initial_cwd, "/tmp/kiwi work")
    handled, layout_changed = actions:handle("reload-config")
    Assert.truthy(handled and not layout_changed)
    Assert.truthy(state.reload_requested)
    Assert.equal(actions:handle("not-an-action"), false)
  end,
  product_action_dispatcher_initializes_then_opens_configuration_without_overwriting = function()
    local actions, state = dispatcher({ explicit_configuration_path = "/tmp/kiwi/config" })
    local handled, layout_changed = actions:handle("open-configuration")
    Assert.truthy(handled and not layout_changed)
    Assert.equal(state.initialized_path, "/tmp/kiwi/config")
    Assert.equal(state.initialization_count, 1)
    Assert.equal(state.configuration_path, "/tmp/kiwi/config")
    Assert.equal(state.configuration.path, "/tmp/kiwi/config")
    Assert.equal(state.opened_paths[1], "/tmp/kiwi/config")
    Assert.truthy(state.initialized_contents:sub(1, 1) == "#")
    actions:handle("open-configuration")
    Assert.equal(state.opened_paths[2], "/tmp/kiwi/config")
    Assert.equal(state.initialized_path, "/tmp/kiwi/config")
  end,
  product_action_dispatcher_keeps_failures_bounded_and_marks_palette_layout_changes = function()
    local actions, state = dispatcher({ palette = "split-right", tab = false, tab_reason = "recording" })
    local handled, layout_changed = actions:handle("new-tab")
    Assert.truthy(handled and not layout_changed)
    Assert.truthy(state.logs[1]:find("tab creation rejected: recording", 1, true) ~= nil)
    handled, layout_changed = actions:handle("command-palette")
    Assert.truthy(handled and not layout_changed)
    Assert.equal(state.palette_entries[1].action, "new-tab")
    Assert.equal(state.layout_marks, 1)
    Assert.equal(state.created_splits[1], "vertical")
  end,
  product_action_dispatcher_preserves_session_move_smoke_metadata = function()
    local actions, state = dispatcher({ session_move_smoke_requester = true })
    local handled, layout_changed = actions:handle("move-session-new-window")
    Assert.truthy(handled and layout_changed)
    Assert.equal(state.move_new_identifier, 17)
    Assert.equal(state.session.session_move_smoke_source_id, 17)
    handled, layout_changed = actions:handle("duplicate-session-next-window")
    Assert.truthy(handled and not layout_changed)
    Assert.truthy(state.duplicate_next)
    handled, layout_changed = actions:handle("duplicate-session-new-window")
    Assert.truthy(handled and not layout_changed)
    Assert.equal(state.window_request.kind, "standalone")
  end,
  product_action_dispatcher_uses_one_bounded_destination_chooser_for_move_and_duplicate = function()
    local targets = { { id = 18, title = "Window 18" }, { id = 29, title = "Window 29" } }
    local actions, state = dispatcher({ palette = "session-target-2", targets = targets })
    local handled, layout_changed = actions:handle("move-session-select-window")
    Assert.truthy(handled and not layout_changed)
    Assert.equal(state.target_source_identifier, 17)
    Assert.equal(state.palette_entries[1].action, "session-target-1")
    Assert.equal(state.palette_entries[2].title, "Window 29")
    Assert.equal(state.move_selected_source_identifier, 17)
    Assert.equal(state.move_selected_target_identifier, 29)
    Assert.equal(state.layout_marks, 1)

    actions, state = dispatcher({ palette = "session-target-1", targets = targets })
    handled, layout_changed = actions:handle("duplicate-session-select-window")
    Assert.truthy(handled and not layout_changed)
    Assert.equal(state.duplicate_selected_source_identifier, 17)
    Assert.equal(state.duplicate_selected_target_identifier, 18)
    Assert.equal(state.layout_marks, 1)
  end,
  product_action_dispatcher_rejects_stale_or_unavailable_destination_selection = function()
    local actions, state = dispatcher({ targets = {} })
    local handled, layout_changed = actions:handle("session-target-1")
    Assert.truthy(handled and not layout_changed)
    Assert.truthy(state.logs[#state.logs]:find("no active destination chooser", 1, true) ~= nil)
    handled, layout_changed = actions:handle("move-session-select-window")
    Assert.truthy(handled and not layout_changed)
    Assert.truthy(state.logs[#state.logs]:find("session target selection rejected", 1, true) ~= nil)
  end,
  product_action_dispatcher_accepts_action_specific_automation_contexts = function()
    local logs = {}
    local created = 0
    local actions = Dispatcher.new({
      create_tab = function()
        created = created + 1
        return true
      end,
      report = function(message) logs[#logs + 1] = message end,
    })
    local handled, layout_changed = actions:handle("new-tab")
    Assert.truthy(handled and layout_changed)
    Assert.equal(created, 1)
    handled, layout_changed = actions:handle("new-window")
    Assert.truthy(handled and not layout_changed)
    Assert.truthy(logs[1]:find("new-window rejected: missing application.request_window", 1, true) ~= nil)

    actions = Dispatcher.new({
      active_session = function() return nil end,
      application = { move_active_to_new_window = function() error("must not move a missing session") end },
      report = function(message) logs[#logs + 1] = message end,
    })
    handled, layout_changed = actions:handle("move-session-new-window")
    Assert.truthy(handled and not layout_changed)
    Assert.truthy(logs[#logs]:find("session move rejected: no active terminal session", 1, true) ~= nil)
  end,
}
