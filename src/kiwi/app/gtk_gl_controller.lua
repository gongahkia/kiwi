-- Experimental single-terminal controller for GtkGLArea presentation.
--
-- It deliberately reuses Kiwi's VT, PTY, input, clipboard, and host-effect
-- boundaries. Workspace composition remains owned by the WGPU controller until
-- the GtkGL renderer can present every pane and image pass with equal evidence.
local AtspiProjection = require("kiwi.accessibility.atspi")
local bit = require("bit")
local ProductActions = require("kiwi.app.actions")
local ProductActionDispatcher = require("kiwi.app.product_action_dispatcher")
local HostEffects = require("kiwi.app.host_effects")
local Clipboard = require("kiwi.input.clipboard")
local Composition = require("kiwi.input.composition")
local Config = require("kiwi.config")
local FontSystem = require("kiwi.font.system")
local Hyperlink = require("kiwi.input.hyperlink")
local HyperlinkPointer = require("kiwi.input.hyperlink_pointer")
local Keyboard = require("kiwi.input.keyboard")
local Mouse = require("kiwi.input.mouse")
local ScrollbarPointer = require("kiwi.input.scrollbar_pointer")
local ScrollbackWheel = require("kiwi.input.scrollback_wheel")
local Pty = require("kiwi.process.pty")
local GtkGLConsumer = require("kiwi.renderer.gtk_gl_consumer")
local GtkGLSession = require("kiwi.app.gtk_gl_session")
local GtkNativeTabGroup = require("kiwi.app.gtk_native_tab_group")
local SelectionPointer = require("kiwi.input.selection_pointer")
local ShellIntegration = require("kiwi.process.shell_integration")
local TextLab = require("kiwi.text.lab")
local Utf8 = require("kiwi.terminal.utf8")
local VT = require("kiwi.vt")
local VTInternal = require("kiwi.vt.internal")

local Controller = {}

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value >= 0 and value or fallback
end

local function positive_number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value > 0 and value or fallback
end

local function dimensions(window, font)
  local width, height = window:drawable_size()
  if width <= 0 or height <= 0 then return nil end
  return math.max(1, math.floor(width / font.cell_width)), math.max(1, math.floor(height / font.cell_height))
end

local function content_scale(window)
  local xscale, yscale = window:content_scale()
  return math.max(xscale, yscale)
end

local function codepoints_from_utf8(text)
  if type(text) ~= "string" then return nil end
  local codepoints = {}
  local invalid = false
  local decoder = Utf8.Decoder.new(function(codepoint, _, replaced)
    if replaced then invalid = true else codepoints[#codepoints + 1] = codepoint end
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  return invalid and nil or codepoints
end

local function new_font(window, configuration)
  local scale = content_scale(window)
  local font = FontSystem.new({
    pixel_height = math.max(1, math.floor(configuration.font_size * scale + 0.5)),
    font_path = configuration.font_path,
    primary_family = configuration.font_family,
    ligatures = configuration.ligatures,
    contextual_alternates = configuration.contextual_alternates,
  })
  font.content_scale = scale
  return font
end

local function consumer_options(configuration)
  return {
    command_region_color = configuration.command_region_color,
    command_region_visual_enabled = configuration.command_regions,
    hyperlink_color = configuration.hyperlink_color,
    search_color = configuration.search_color,
    selection_color = configuration.selection_color,
    scrollbar_policy = configuration.scrollbar,
    text_backend = TextLab.requested_backend(),
  }
end

local function requested_unsupported_option(options)
  local names = {
    { "record", "recording" },
    { "inspect", "text inspection" },
    { "workspace_smoke", "workspace smoke" },
    { "menu_smoke", "native product-menu smoke" },
    { "toolbar_smoke", "native toolbar smoke" },
    { "cwd_smoke", "native current-directory smoke" },
    { "palette_smoke", "native command-palette smoke" },
    { "automation_smoke", "native automation smoke" },
    { "key_sequence_smoke", "key-sequence smoke" },
    { "multi_window_smoke", "multi-window smoke" },
    { "session_move_smoke", "session-move smoke" },
    { "moved_session", "session transfer" },
    { "restored_workspace", "workspace restore" },
    { "host_tab", "host tab request" },
  }
  for _, item in ipairs(names) do
    if options[item[1]] then return item[2] end
  end
end

function Controller.validate_options(options)
  assert(type(options) == "table", "GTK GL controller options must be a table")
  local unsupported = requested_unsupported_option(options)
  if unsupported then return nil, unsupported .. " is unavailable with KIWI_GTK_PRESENTER=gl" end
  return true
end

local function report_clipboard_failure(operation, status)
  io.stderr:write("Kiwi clipboard ", operation, " rejected: ", status:gsub("_", " "), "\n")
end

local function report_hyperlink_failure(status)
  if status ~= "no-link" then io.stderr:write("Kiwi hyperlink activation rejected: ", (status or "unavailable"):gsub("-", " "), "\n") end
end

local function report_region_status(status)
  if status ~= "navigated" then io.stderr:write("Kiwi regions: ", status:gsub("-", " "), "\n") end
end

-- This route is deliberately opt-in while its Linux graphical qualification is
-- incomplete. Unlike the single-page route below, every native tab owns a
-- distinct VT, PTY, input correlation state, IM context, accessibility
-- projection, font, and GtkGL renderer through GtkGLSession.
function Controller.run_native_tabs(window, host, options)
  local supported, reason = Controller.validate_options(options)
  assert(supported, reason)
  assert(host.platform == "GTK", "GtkGLArea native tabs need the GTK host")
  local system_appearance = host.system_appearance and host.system_appearance(window) or nil
  local configuration, configuration_path = Config.load(options.config, nil, {
    appearance = system_appearance,
    command_line_overrides = options.configuration_overrides,
  })
  local enabled, enable_reason = window:enable_native_tabs()
  assert(enabled, "GTK native tabs could not be enabled: " .. tostring(enable_reason))
  local tab_group = GtkNativeTabGroup.new(window)
  local sessions = tab_group.sessions
  local product_actions = ProductActions.new(configuration.keybindings, host.keymap)
  local action_dispatcher
  local started_at = window:time()
  local max_seconds = number_from_env("KIWI_MAX_SECONDS", 0)

  local function close_session(session)
    return tab_group:close(session)
  end

  local function handle_product_key(session, key, action, modifiers)
    if bit.band(session.state.modes.keyboard_flags, 8) ~= 0 then
      product_actions:reset_sequence()
      return false
    end
    if action ~= host.keymap.press then return false end
    local product_action, status = product_actions:lookup(key, modifiers, session.window:time())
    if product_action ~= nil then
      action_dispatcher.current_session = session
      local handled = action_dispatcher and action_dispatcher:handle(product_action)
      return handled == true
    end
    return status == "pending"
  end

  local function create_session(page, command, initial_cwd)
    local session = GtkGLSession.new(page, host, configuration, {
      command = command,
      default_title = "Kiwi GTK GL terminal",
      initial_cwd = initial_cwd,
      is_selected = function(page) return window:selected_native_tab() == page end,
      on_product_key = handle_product_key,
    })
    return tab_group:add(session)
  end

  local function active_working_directory()
    local session = action_dispatcher and action_dispatcher.current_session or sessions[1]
    return Pty.local_working_directory(session and session.state.shell.current_directory or nil)
  end

  local function create_tab()
    local page = window:new_native_tab("Kiwi GTK GL terminal")
    create_session(page, options.command, active_working_directory())
    return true
  end

  local function focus_next_tab()
    local selected, selected_reason = window:select_next_native_tab()
    return selected == true, selected_reason
  end

  action_dispatcher = ProductActionDispatcher.new({
    active_session = function() return action_dispatcher and action_dispatcher.current_session or sessions[1] end,
    application = options.application,
    close_active_pane = function()
      -- GTK delivers key input to the selected page, so the product callback
      -- below replaces this with that page before dispatching close.
      return nil, "native-tab-selection-required"
    end,
    configuration = function() return configuration end,
    configuration_path = function() return configuration_path end,
    create_split = function() return nil, "splits are unavailable with KIWI_GTK_PRESENTER=gl" end,
    create_tab = create_tab,
    explicit_configuration_path = options.config,
    focus_next_tab = function() return focus_next_tab() end,
    host = host,
    initial_working_directory = active_working_directory,
    report = function(message) io.stderr:write(message, "\n") end,
    request_configuration_reload = function()
      io.stderr:write("Kiwi configuration reload is unavailable with GTK native tabs; restart the terminal.\n")
    end,
    set_configuration_path = function(path) configuration_path = path; configuration.path = path end,
    window = window,
  })

  -- ProductActionDispatcher is host-neutral, but close needs the page that
  -- generated the current event. Keep that state in a narrow wrapper rather
  -- than passing GTK pointers into terminal state.
  local dispatch_product = action_dispatcher.handle
  function action_dispatcher:handle(action)
    if action == "close-pane" then
      local target = self.current_session
      if target == nil then return true, false end
      local closed, close_reason = close_session(target)
      if not closed then io.stderr:write("Kiwi pane closure rejected: ", tostring(close_reason), "\n") end
      return true, closed == true
    end
    return dispatch_product(self, action)
  end

  local root_session = create_session(window, options.command, options.initial_cwd)
  action_dispatcher.current_session = root_session
  local close_handler_enabled, close_handler_reason = window:set_native_tab_close_handler(function(page)
    for _, session in ipairs(sessions) do
      if session.window == page then
        local closed = close_session(session)
        return closed == true
      end
    end
    return false
  end)
  assert(close_handler_enabled, "GTK native tab close handler could not be installed: " .. tostring(close_handler_reason))
  if host.set_product_action_handler then
    local menu_enabled, menu_reason = host.set_product_action_handler(window, function(action)
      local selected = window:selected_native_tab()
      for _, session in ipairs(sessions) do
        if session.window == selected then action_dispatcher.current_session = session; break end
      end
      action_dispatcher:handle(action)
    end)
    if not menu_enabled then io.stderr:write("Kiwi native menu unavailable: ", tostring(menu_reason), "\n") end
  end
  if os.getenv("KIWI_GTK_NATIVE_TABS_SMOKE") == "1" then
    assert(host.invoke_product_action_smoke, "GTK native-tab smoke needs the product-action bridge")
    local invoked, invoke_reason = host.invoke_product_action_smoke(window, "new-tab")
    assert(invoked, "GTK native-tab smoke could not invoke New Tab: " .. tostring(invoke_reason))
    assert(#sessions == 2, "GTK native-tab smoke did not create a distinct terminal session")
    assert(sessions[1].window ~= sessions[2].window and sessions[1].pty ~= sessions[2].pty,
      "GTK native-tab smoke did not retain independent page and PTY ownership")
    if os.getenv("KIWI_GTK_NATIVE_TABS_CLOSE_SMOKE") == "1" then
      local close_invoked, close_reason = host.invoke_product_action_smoke(window, "close-pane")
      assert(close_invoked, "GTK native-tab close smoke could not invoke Close Pane: " .. tostring(close_reason))
      assert(#sessions == 1 and window:native_tab_count() == 1,
        "GTK native-tab close smoke did not release exactly one page and session")
      assert(not sessions[1].closed,
        "GTK native-tab close smoke released the session that remained visible")
    end
  end

  io.stdout:write(string.format("Kiwi GTK GL native-tabs experimental: TERM=xterm-kiwi child=%s tabs=%d\n",
    options.command and options.command[1] or Pty.default_command()[1], #sessions))
  local ok, result = xpcall(function()
    while not window:should_close() and #sessions > 0 do
      local now = window:time()
      if max_seconds > 0 and now - started_at >= max_seconds then break end
      local timeout = 0.050
      for _, session in ipairs(sessions) do
        local deadline = session:next_deadline()
        if deadline and deadline > now then timeout = math.min(timeout, deadline - now) else timeout = 0 end
      end
      if host.await_events and options.application then
        host.await_events(options.application, window, math.max(0, timeout))
      else
        window:wait_events(math.max(0, timeout))
      end
      if window:should_close() then break end
      local all_complete = true
      for index = #sessions, 1, -1 do
        local session = sessions[index]
        action_dispatcher.current_session = session
        if not session.complete then session.complete = session:tick(window:time()) == "complete" end
        if not session.complete then all_complete = false end
      end
      if os.getenv("KIWI_GTK_NATIVE_TABS_SMOKE") == "1" and not all_complete then
        for _, session in ipairs(sessions) do
          if not session.complete then
            assert(session.window:select_native_tab())
            break
          end
        end
      end
      if all_complete then window:request_close() end
    end
  end, debug.traceback)
  tab_group:shutdown()
  window:destroy()
  if not ok then error(result) end
end

function Controller.run(window, host, options)
  if os.getenv("KIWI_GTK_NATIVE_TABS") == "1" then
    return Controller.run_native_tabs(window, host, options)
  end
  local supported, reason = Controller.validate_options(options)
  assert(supported, reason)
  assert(host.platform == "GTK", "GtkGLArea presentation needs the GTK host")

  local font
  local terminal
  local pty
  local consumer
  local accessibility
  local ok, result = xpcall(function()
    local default_title = "Kiwi GTK GL terminal"
    local glfw = host.keymap
    local system_appearance = host.system_appearance and host.system_appearance(window) or nil
    local configuration, configuration_path = Config.load(options.config, nil, {
      appearance = system_appearance,
      command_line_overrides = options.configuration_overrides,
    })
    font = new_font(window, configuration)
    local columns, rows = assert(dimensions(window, font), "window has no drawable size")
    local function new_terminal(child_columns, child_rows)
      return VT.new({
        columns = child_columns,
        rows = child_rows,
        state_options = {
          scrollback_limit = configuration.scrollback_limit,
          ambiguous_width = configuration.ambiguous_width,
          osc52_read = configuration.osc52_read == "allow",
          osc52_write = configuration.osc52_write,
          keyboard_supported_flags = host.keyboard_supported_flags_for and
            host.keyboard_supported_flags_for(window) or host.keyboard_supported_flags,
          cell_width = font.cell_width,
          cell_height = font.cell_height,
          colors = {
            foreground = configuration.foreground,
            background = configuration.background,
            palette = configuration.palette,
          },
        },
      })
    end
    local function spawn_child(command, child_columns, child_rows)
      local root = os.getenv("KIWI_ROOT") or "."
      local environment = {
        TERM = "xterm-kiwi",
        TERMINFO = os.getenv("KIWI_TERMINFO") or root .. "/.build/terminfo",
        COLORTERM = "truecolor",
      }
      if command == nil and configuration.shell_integration == "auto" then
        local integration_environment
        command, integration_environment = ShellIntegration.prepare(Pty.default_command(), os.getenv("KIWI_INTEGRATION_DIR") or root .. "/integrations/v1")
        for name, value in pairs(integration_environment) do environment[name] = value end
      else
        command = command or Pty.default_command()
        if configuration.shell_integration == "none" then environment.KIWI_SHELL_INTEGRATION = false end
      end
      return Pty.spawn(command, child_columns, child_rows, environment)
    end

    terminal = new_terminal(columns, rows)
    local state = VTInternal.state(terminal)
    pty = spawn_child(options.command, columns, rows)
    local clipboard = Clipboard.new(window)
    configuration.host_effects = HostEffects.new(configuration, host, window)
    local hyperlink = Hyperlink.new(window)
    local hyperlink_pointer = HyperlinkPointer.new(hyperlink, glfw)
    local mouse = Mouse.new()
    local scrollback_wheel = ScrollbackWheel.new()
    local scrollbar_pointer = ScrollbarPointer.new()
    local selection_pointer = SelectionPointer.new()
    local composition = Composition.new()
    composition:enter()
    local last_title = default_title
    local window_focused = true
    local frames = 0
    local max_frames = number_from_env("KIWI_MAX_FRAMES", 0)
    local max_seconds = number_from_env("KIWI_MAX_SECONDS", 0)
    local started_at = window:time()
    local read_budget = number_from_env("KIWI_PTY_READ_BUDGET", 4 * 1024)
    local render_timeout = positive_number_from_env("KIWI_GTK_GL_RENDER_TIMEOUT", 3)
    local render_target_deadline
    local render_target_revision
    local next_revision

    consumer = GtkGLConsumer.new(window, font, state, consumer_options(configuration))
    local accessibility_reason
    accessibility, accessibility_reason = host.accessibility_new and host.accessibility_new(window) or nil, "unavailable for this host"
    if accessibility == nil and os.getenv("KIWI_ACCESSIBILITY_DIAGNOSTICS") == "1" then
      io.stderr:write("Kiwi accessibility: unavailable: ", accessibility_reason, "\n")
    end
    local accessibility_projection = AtspiProjection.new()

    local function enqueue_input(bytes)
      if bytes and #bytes > 0 then pty:enqueue(bytes) end
    end

    local function invalidate(reason_name)
      consumer:invalidate(reason_name or "terminal")
    end

    local function update_preedit_overlay(update)
      local preedit = update.preedit
      if preedit.text == "" then
        state.ime_preedit = nil
      else
        state.ime_preedit = {
          column = state.cursor.column,
          cursor_begin = preedit.cursor_begin,
          cursor_end = preedit.cursor_end,
          row = state.cursor.row,
          text = preedit.text,
        }
      end
      invalidate("terminal")
    end

    local function apply_preedit(text, selection_start, selection_end)
      if not composition.focused then composition:enter() end
      local accepted, status = composition:offer_preedit(text, selection_start, selection_end)
      if not accepted then
        io.stderr:write("Kiwi IME preedit rejected: ", status, "\n")
        return
      end
      update_preedit_overlay(assert(composition:done()))
    end

    local function apply_commit(text)
      if not composition.focused then composition:enter() end
      local accepted = composition:offer_preedit("", 0, 0)
      if accepted then update_preedit_overlay(assert(composition:done())) end
      local status
      accepted, status = composition:offer_commit(text)
      if not accepted then
        io.stderr:write("Kiwi IME commit rejected: ", status, "\n")
        return nil
      end
      local update = assert(composition:done())
      update_preedit_overlay(update)
      return update.commit
    end

    local function handle_committed_text(text)
      if text == nil or #text == 0 then return end
      local search = state:search_view()
      if search.editing and search.visible then
        local appended, status = state:search_append(text)
        if not appended then io.stderr:write("Kiwi search: ", status:gsub("-", " "), "\n") end
        invalidate("search")
      else
        enqueue_input(text)
      end
    end

    local function handle_search_key(key, action)
      local search = state:search_view()
      if not search.editing or not search.visible then return false end
      if key == glfw.key_escape then
        if action == glfw.press then state:clear_search() end
        return true
      end
      if key == glfw.key_backspace then
        if action == glfw.press or action == glfw.repeat_action then state:search_backspace() end
        return true
      end
      if key == glfw.key_enter then
        if action == glfw.press then
          local _, status = state:search_submit("forward")
          if status ~= "matches" then io.stderr:write("Kiwi search: ", status:gsub("-", " "), "\n") end
        end
        return true
      end
      return false
    end

    local function handle_local_action(encoded)
      if encoded.local_action == "scroll_up" then
        state:scroll_history(math.max(1, state.rows - 1))
        invalidate("terminal")
      elseif encoded.local_action == "scroll_down" then
        state:scroll_history(-math.max(1, state.rows - 1))
        invalidate("terminal")
      elseif encoded.local_action and encoded.local_action:match("^region_") then
        local direction, role = encoded.local_action:match("^region_([^_]+)_([^_]+)$")
        local _, status = state:navigate_command_region(role, direction == "next" and "forward" or "backward")
        report_region_status(status)
        invalidate("terminal")
      elseif encoded.local_action == "copy" then
        local copied, status = clipboard:copy(state)
        if not copied then report_clipboard_failure("copy", status) end
      elseif encoded.local_action == "paste" then
        local bytes, status = clipboard:paste(state)
        if bytes then enqueue_input(bytes) elseif status ~= "empty" then report_clipboard_failure("paste", status) end
      elseif encoded.local_action == "search_begin" then
        state:search_begin("forward")
        invalidate("search")
      elseif encoded.local_action == "search_next" or encoded.local_action == "search_previous" then
        local direction = encoded.local_action == "search_next" and "forward" or "backward"
        local search = state:search_view()
        local _, status = search.editing and search.visible and state:search_submit(direction) or state:search_navigate(direction)
        if status ~= "matches" then io.stderr:write("Kiwi search: ", status:gsub("-", " "), "\n") end
        invalidate("search")
      elseif encoded.local_action == "open_hyperlink" then
        local opened, status = hyperlink:activate(state:hyperlink_at_cursor())
        if not opened then report_hyperlink_failure(status) end
      elseif encoded.bytes then
        enqueue_input(encoded.bytes)
      end
    end

    window:set_input_handlers(function(codepoints, key_event)
      if key_event then
        apply_commit("")
        local encoded = Keyboard.key(key_event.key, key_event.action, key_event.modifiers, state.modes, glfw, {
          associated_text = codepoints,
          unicode_key = key_event.variants and key_event.variants.unicode_key,
          layout_key = key_event.variants and key_event.variants.layout_key,
          shifted_key = key_event.variants and key_event.variants.shifted_key,
          base_key = key_event.variants and key_event.variants.base_key,
        })
        if encoded then handle_local_action(encoded) end
        return
      end
      handle_committed_text(Keyboard.text_sequence(codepoints, state.modes))
    end, function(key, action, modifiers, variants)
      if handle_search_key(key, action) then
        invalidate("search")
        return { handled = true, suppress_text = true }
      end
      if Keyboard.should_defer_text(key, action, modifiers, state.modes, glfw, variants) then
        return { handled = true, defer_text = true }
      end
      local encoded = Keyboard.key(key, action, modifiers, state.modes, glfw, variants)
      if not encoded then return nil end
      handle_local_action(encoded)
      return { handled = true, suppress_text = encoded.suppress_text }
    end, function(event)
      event.time = window:time()
      local scale = font.content_scale or 1
      event.selection_column, event.selection_row = SelectionPointer.cell_position(event.x, event.y, scale, font.cell_width, font.cell_height, state.columns, state.rows)
      event.column = event.selection_column + 1
      event.row = event.selection_row + 1
      event.pixel_width = math.max(1, math.floor(state.columns * font.cell_width))
      event.pixel_height = math.max(1, math.floor(state.rows * font.cell_height))
      event.pixel_x = math.max(1, math.min(event.pixel_width, math.floor(event.x * scale) + 1))
      event.pixel_y = math.max(1, math.min(event.pixel_height, math.floor(event.y * scale) + 1))
      local scrollbar_handled, scrollbar_changed = scrollbar_pointer:handle(event, state,
        ScrollbarPointer.descriptor(state, configuration.scrollbar))
      if scrollbar_changed then invalidate("scrollbar") end
      local hyperlink_handled, hyperlink_opened, hyperlink_status = false, false, nil
      if not scrollbar_handled then hyperlink_handled, hyperlink_opened, hyperlink_status = hyperlink_pointer:handle(event, state, state.modes) end
      if hyperlink_handled and not hyperlink_opened then report_hyperlink_failure(hyperlink_status) end
      local selection_handled, selection_changed = false, false
      if not scrollbar_handled and not hyperlink_handled then selection_handled, selection_changed = selection_pointer:handle(event, state, state.modes, configuration.mouse_shift_capture) end
      if selection_changed then invalidate("selection") end
      if not scrollbar_handled and not hyperlink_handled and not selection_handled then
        local encoded
        if event.kind == "button" then encoded = mouse:button(event, state:input_modes())
        elseif event.kind == "motion" then encoded = mouse:motion(event, state:input_modes())
        elseif event.kind == "wheel" then
          local history_lines = scrollback_wheel:consume(event, state:input_modes())
          if history_lines ~= nil then
            state:scroll_history(history_lines)
            invalidate("terminal")
          else
            encoded = mouse:wheel(event, state:input_modes())
          end
        end
        if encoded then enqueue_input(encoded) end
      end
    end, function(focused)
      window_focused = focused
      if focused then
        composition:enter()
      else
        selection_pointer:reset()
        scrollbar_pointer:reset()
        state.ime_preedit = nil
        composition:leave()
        invalidate("terminal")
      end
      local encoded = mouse:focus(focused, state:input_modes())
      if encoded then enqueue_input(encoded) end
    end)
    local text_input_enabled, text_input_reason = host.enable_text_input(window, apply_preedit, function(text)
      local committed = apply_commit(text)
      local codepoints = codepoints_from_utf8(committed)
      handle_committed_text(codepoints and Keyboard.text_sequence(codepoints, state.modes) or nil)
    end)
    if not text_input_enabled then io.stderr:write("Kiwi IME: unavailable: ", text_input_reason, "\n") end

    local function sync_text_input_caret()
      if type(host.set_text_input_caret) ~= "function" then return end
      local scale = font.content_scale or 1
      host.set_text_input_caret(window,
        state.cursor.column * font.cell_width / scale,
        state.cursor.row * font.cell_height / scale,
        math.max(1, font.cell_width / scale),
        math.max(1, font.cell_height / scale)
      )
    end

    local function sync_accessibility()
      if accessibility == nil then return end
      local projection = accessibility_projection:project(state)
      local updated, update_reason = accessibility:update(projection, last_title, window_focused)
      if updated then
        accessibility:poll()
      else
        accessibility:destroy()
        accessibility = nil
        if os.getenv("KIWI_ACCESSIBILITY_DIAGNOSTICS") == "1" then
          io.stderr:write("Kiwi accessibility: disabled after provider failure: ", update_reason, "\n")
        end
      end
    end

    local function recreate_consumer()
      if consumer ~= nil then
        next_revision = consumer.revision
        consumer:destroy()
      end
      consumer = GtkGLConsumer.new(window, font, state, {
        command_region_color = configuration.command_region_color,
        command_region_visual_enabled = configuration.command_regions,
        hyperlink_color = configuration.hyperlink_color,
        next_revision = next_revision,
        search_color = configuration.search_color,
        selection_color = configuration.selection_color,
        scrollbar_policy = configuration.scrollbar,
        text_backend = TextLab.requested_backend(),
      })
      next_revision = nil
    end

    local function await_rendered_target(now)
      if render_target_revision == nil then return false end
      local gl_state, state_reason = window:gl_area_state()
      if gl_state and gl_state.rendered_revision >= render_target_revision then
        if os.getenv("KIWI_GTK_GL_REPORT") == "1" then
          io.stdout:write(string.format("Kiwi GTK GL render smoke passed: rendered revision=%d.\n", gl_state.rendered_revision))
        end
        return true
      end
      if now >= render_target_deadline then
        error("Kiwi GTK GL presentation did not render revision " .. tostring(render_target_revision) .. ": " .. tostring(state_reason or "render callback timed out"))
      end
      return false
    end

    io.stdout:write(string.format("Kiwi GTK GL experimental: TERM=xterm-kiwi child=%s grid=%dx%d primary=%s\n",
      options.command and options.command[1] or Pty.default_command()[1], columns, rows, font.font_path))
    while not window:should_close() do
      local now = window:time()
      if max_seconds > 0 and now - started_at >= max_seconds then break end
      local deadline = consumer:next_render_deadline()
      local requested_wait = deadline and now < deadline and math.min(deadline - now, 0.050) or 0.050
      if host.await_events and options.application then
        host.await_events(options.application, window, requested_wait)
      else
        window:wait_events(requested_wait)
      end
      if window:should_close() then break end

      if await_rendered_target(window:time()) then break end

      local scale_changed = math.abs(content_scale(window) - font.content_scale) > 0.001
      local new_columns, new_rows = dimensions(window, font)
      if scale_changed then
        local previous_font = font
        next_revision = consumer.revision
        consumer:destroy()
        consumer = nil
        font = new_font(window, configuration)
        terminal:set_cell_metrics(font.cell_width, font.cell_height)
        new_columns, new_rows = assert(dimensions(window, font), "window has no drawable size")
        previous_font:destroy()
        window.resized = true
      end
      if window.resized or new_columns ~= columns or new_rows ~= rows then
        columns, rows = new_columns, new_rows
        terminal:resize(columns, rows)
        pty:resize(columns, rows)
        window.resized = false
        recreate_consumer()
      end

      local output = pty:read_available(read_budget)
      if #output > 0 then
        terminal:write(output)
        invalidate("terminal")
      end
      local responses = terminal:pop_responses()
      if #responses > 0 then pty:enqueue(table.concat(responses)) end
      for _, effect in ipairs(terminal:pop_effects()) do
        if effect.kind == "clipboard_write_requested" then
          local written, status = clipboard:write_osc52(effect.value.text)
          if not written then io.stderr:write("Kiwi OSC 52 clipboard write rejected: ", status, "\n") end
        elseif effect.kind == "clipboard_read_requested" then
          local reply, status = clipboard:read_osc52_reply(effect.value.selection, effect.value.maximum_bytes)
          if reply then pty:enqueue(reply) else io.stderr:write("Kiwi OSC 52 clipboard read rejected: ", status, "\n") end
        elseif effect.kind == "pointer_shape_changed" and host.set_pointer_shape then
          host.set_pointer_shape(window, effect.value.shape)
        else
          local consumed, status, first_report = configuration.host_effects:consume(effect, {
            focused = window_focused,
            now = now,
            source = terminal,
          })
          if consumed and first_report and (status == "invalid" or status == "unavailable" or status == "rejected") then
            local subject = effect.kind == "shell_marker" and "command-finish notification"
              or effect.kind == "notification_requested" and "OSC 9 notification" or "OSC 9 progress"
            io.stderr:write("Kiwi ", subject, " ignored: ", status, "\n")
          end
        end
      end
      pty:flush()
      local child_status = pty:poll_exit()

      local search = state:search_view()
      local title = search.editing and search.visible and "Kiwi search: " .. search.query or state.title or default_title
      if title ~= last_title then
        window:set_title(title)
        last_title = title
      end
      sync_accessibility()
      sync_text_input_caret()

      now = window:time()
      if render_target_revision == nil and not window.minimized and consumer:needs_render(now) then
        local rendered, render_reason = consumer:render(state, now, window.debug_dirty, window.debug_boundaries)
        if rendered then
          frames = frames + 1
          if max_frames > 0 and frames >= max_frames then
            render_target_revision = consumer.revision - 1
            render_target_deadline = window:time() + render_timeout
          end
        elseif render_reason ~= "synchronized-output" then
          error("Kiwi GTK GL presentation rejected a frame: " .. tostring(render_reason))
        end
      end
      if child_status and pty.eof and render_target_revision == nil then
        render_target_revision = consumer.revision - 1
        render_target_deadline = window:time() + render_timeout
      end
    end
    terminal:finish()
  end, debug.traceback)

  if accessibility then accessibility:destroy() end
  if consumer then consumer:destroy() end
  if pty then pty:shutdown() end
  if terminal then terminal:close() end
  if font then font:destroy() end
  window:destroy()
  if not ok then error(result) end
end

return Controller
