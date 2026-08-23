-- Internal terminal/session/renderer controller shared by native hosts.
local Context = require("kiwi.gpu.context")
local AtspiProjection = require("kiwi.accessibility.atspi")
local ProductActions = require("kiwi.app.actions")
local bit = require("bit")
local Recovery = require("kiwi.gpu.recovery")
local DeviceSoak = require("kiwi.bench.device_soak")
local Pacing = require("kiwi.bench.pacing")
local Power = require("kiwi.bench.power")
local TextInspector = require("kiwi.diagnostics.text_inspector")
local FontSystem = require("kiwi.font.system")
local Clipboard = require("kiwi.input.clipboard")
local Composition = require("kiwi.input.composition")
local Config = require("kiwi.config")
local Hyperlink = require("kiwi.input.hyperlink")
local HyperlinkPointer = require("kiwi.input.hyperlink_pointer")
local Keyboard = require("kiwi.input.keyboard")
local Metrics = require("kiwi.diagnostics.metrics")
local Mouse = require("kiwi.input.mouse")
local SelectionPointer = require("kiwi.input.selection_pointer")
local Pty = require("kiwi.process.pty")
local ShellIntegration = require("kiwi.process.shell_integration")
local Compositor = require("kiwi.renderer.compositor")
local Renderer = require("kiwi.renderer.renderer")
local Workspace = require("kiwi.session.workspace")
local TextLab = require("kiwi.text.lab")
local Replay = require("kiwi.terminal.replay")
local Utf8 = require("kiwi.terminal.utf8")
local VT = require("kiwi.vt")
local VTInternal = require("kiwi.vt.internal")

local Controller = {}

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value >= 0 and value or fallback
end

local function dimensions(window, font)
  local width, height = window:drawable_size()
  if width <= 0 or height <= 0 then
    return nil
  end
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

local function extension_modules()
  local configured = os.getenv("KIWI_RENDER_EXTENSIONS")
  if configured == nil or #configured == 0 then return {} end
  local modules = {}
  for module in configured:gmatch("[^,]+") do modules[#modules + 1] = module end
  return modules
end

local function extension_limit_from_env(name, minimum, maximum, integer)
  local value = os.getenv(name)
  if value == nil or #value == 0 then return nil end
  local number = tonumber(value)
  assert(number and number >= minimum and (not integer or number % 1 == 0) and (maximum == nil or number <= maximum), name .. " must be a " .. (integer and "integer" or "number") .. " between " .. minimum .. (maximum and " and " .. maximum or " and infinity"))
  return number
end

local function renderer_options(runtime_options, configuration)
  local release_mode = runtime_options.release_mode == true
  local options = {
    pass_metrics_enabled = not release_mode and os.getenv("KIWI_PASS_METRICS") == "1",
    pass_budgets_enabled = not release_mode and os.getenv("KIWI_PASS_BUDGETS") == "1",
    inspector_enabled = not release_mode and os.getenv("KIWI_RENDER_INSPECTOR") == "1",
    inspector_selected_pass = not release_mode and os.getenv("KIWI_RENDER_INSPECTOR_PASS") or nil,
    selection_color = configuration.selection_color,
    search_color = configuration.search_color,
    hyperlink_color = configuration.hyperlink_color,
    command_region_visual_enabled = configuration.command_regions,
    command_region_color = configuration.command_region_color,
    text_backend = TextLab.requested_backend(),
    extensions_enabled = not runtime_options.no_extensions,
    extensions = {},
  }
  if not runtime_options.no_extensions then
    options.extensions = extension_modules()
    options.extension_pass_limit = extension_limit_from_env("KIWI_EXTENSION_MAX_PASSES", 1, nil, true)
    options.extension_animation_hz = extension_limit_from_env("KIWI_EXTENSION_MAX_ANIMATION_HZ", 1 / 60, 60, false)
  end
  if release_mode or os.getenv("KIWI_DEVELOPMENT") ~= "1" then return options end
  local path = os.getenv("KIWI_DEV_SHADER_PATH")
  assert(type(path) == "string" and #path > 0, "KIWI_DEVELOPMENT=1 needs KIWI_DEV_SHADER_PATH")
  options.development_mode = true
  options.development_shader_path = path
  return options
end

local function report_shader_reload(reloaded, message)
  if reloaded == true then
    io.stdout:write("Kiwi shader reload: ", message, "\n")
  elseif reloaded == false then
    io.stderr:write("Kiwi shader reload: ", message, "\n")
  end
end

local function report_gpu_timing(renderer)
  local timing = renderer.diagnostics.gpu_timing or { enabled = false, status = "unavailable", samples = {} }
  io.stdout:write(string.format("Kiwi GPU timing: enabled=%s status=%s pending=%d dropped=%d samples=%d\n", tostring(timing.enabled), timing.status, timing.pending or 0, timing.dropped or 0, #timing.samples))
  for _, sample in ipairs(timing.samples) do
    io.stdout:write(string.format("Kiwi GPU timing sample: frame=%d pass=%s ticks=%d map-latency=%.3fms\n", sample.frame, sample.name, sample.gpu_ticks, sample.map_latency_ms))
  end
end

local function report_pass_budgets(renderer)
  local budgets = renderer.diagnostics.pass_budgets or { enabled = false, warnings = {}, passes = {} }
  io.stdout:write(string.format("Kiwi pass budgets: enabled=%s warnings=%d passes=%d\n", tostring(budgets.enabled), #budgets.warnings, #budgets.passes))
  for _, warning in ipairs(budgets.warnings) do
    io.stdout:write(string.format("Kiwi pass budget warning: pass=%s dimension=%s frame=%d average=%.6f limit=%.6f window=%d\n", warning.pass, warning.dimension, warning.frame, warning.average, warning.limit, warning.window))
  end
end

local function report_framebuffer_capture(context)
  local capture = context:framebuffer_capture_snapshot()
  io.stdout:write(string.format("Kiwi framebuffer capture: samples=%d pending=%d dropped=%d\n", #capture.samples, capture.pending, capture.dropped))
  for _, sample in ipairs(capture.samples) do
    io.stdout:write(string.format(
      "Kiwi framebuffer sample: frame=%d checksum=%s opaque=%d red=%d blue=%d\n",
      sample.frame,
      sample.checksum,
      sample.opaque_pixels,
      sample.red_dominant_pixels,
      sample.blue_dominant_pixels
    ))
    if capture.expected_rgb then
      io.stdout:write(string.format(
        "Kiwi framebuffer expected RGB: frame=%d rgb=%d,%d,%d tolerance=%d pixels=%d\n",
        sample.frame,
        capture.expected_rgb.red,
        capture.expected_rgb.green,
        capture.expected_rgb.blue,
        capture.expected_rgb.tolerance,
        sample.expected_rgb_pixels
      ))
    end
    io.stdout:write(string.format(
      "Kiwi framebuffer modal RGB: frame=%d rgb=%d,%d,%d pixels=%d\n",
      sample.frame,
      math.floor(sample.modal_rgb / 65536) % 256,
      math.floor(sample.modal_rgb / 256) % 256,
      sample.modal_rgb % 256,
      sample.modal_rgb_pixels
    ))
  end
end

function Controller.run(window, host, options)
  local default_title = "Kiwi M2 terminal"
  local glfw = host.keymap
  local system_appearance = host.system_appearance and host.system_appearance(window) or nil
  local function load_configuration()
    return Config.load(options.config, nil, {
      appearance = system_appearance,
      command_line_overrides = options.configuration_overrides,
    })
  end
  local configuration, configuration_path = load_configuration()
  local product_actions = ProductActions.new(configuration.keybindings, glfw)
  local started_at = window:time()
  if geometry then window:set_position(geometry.x, geometry.y) end
  local context
  local compositor
  local renderer
  local font
  local pty
  local recorder
  local terminal
  local accessibility
  local workspace
  local pane_entries = {}
  local pane_layouts = {}
  local workspace_columns
  local workspace_rows
  local destroy_session
  local ok, result = xpcall(function()
    local context_options = {
      framebuffer_capture = os.getenv("KIWI_FRAMEBUFFER_CAPTURE") == "1",
      framebuffer_expected_rgb = os.getenv("KIWI_FRAMEBUFFER_EXPECT_RGB"),
      gpu_timestamps = not options.release_mode and os.getenv("KIWI_GPU_TIMESTAMPS") == "1",
    }
    context = Context.new(host, window, context_options)
    compositor = Compositor.new(context)
    if os.getenv("KIWI_TIMESTAMP_PROBE") == "1" then
      local probe_ok, probe_message = context:probe_timestamp_queries()
      io.stderr:write("Kiwi timestamp probe: ", probe_ok and "supported: " or "unavailable: ", probe_message, "\n")
    end
    font = new_font(window, configuration)
    local columns, rows = dimensions(window, font)
    assert(columns ~= nil, "window has no drawable size")
    workspace_columns = columns
    workspace_rows = rows
    local function new_terminal(child_columns, child_rows)
      return VT.new({
        columns = child_columns,
        rows = child_rows,
        state_options = {
          scrollback_limit = configuration.scrollback_limit,
          ambiguous_width = configuration.ambiguous_width,
          osc52_write = configuration.osc52_write,
          keyboard_supported_flags = host.keyboard_supported_flags,
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
    local root = os.getenv("KIWI_ROOT") or "."
    local terminfo_directory = os.getenv("KIWI_TERMINFO") or root .. "/.build/terminfo"
    local integration_directory = os.getenv("KIWI_INTEGRATION_DIR") or root .. "/integrations/v1"
    local function spawn_child(command, child_columns, child_rows)
      local environment = {
        TERM = "xterm-kiwi",
        TERMINFO = terminfo_directory,
        COLORTERM = "truecolor",
      }
      if command == nil and configuration.shell_integration == "auto" then
        local integration_environment
        command, integration_environment = ShellIntegration.prepare(Pty.default_command(), integration_directory)
        for name, value in pairs(integration_environment) do environment[name] = value end
      else
        command = command or Pty.default_command()
        if configuration.shell_integration == "none" then environment.KIWI_SHELL_INTEGRATION = false end
      end
      return Pty.spawn(command, child_columns, child_rows, environment)
    end
    local render_options = renderer_options(options, configuration)
    local clipboard = Clipboard.new(window)
    configuration.host_effects = require("kiwi.app.host_effects").new(configuration, host, window)
    local hyperlink = Hyperlink.new(window)
    local active_session
    local state
    local parser
    local recovery
    local metrics
    local mouse
    local mouse_generation
    local selection_pointer
    local composition
    if options.moved_session then
      active_session = options.moved_session
      terminal = active_session.terminal
      state = VTInternal.state(terminal)
      pty = active_session.pty
      parser = VTInternal.parser(terminal)
      recovery = active_session.recovery
      if active_session.renderer then
        active_session.renderer:destroy()
        active_session.renderer = nil
      end
      renderer = nil
      metrics = active_session.metrics
      metrics.context = context
      metrics.font = font
      metrics.model = state
      metrics:set_runtime({ clipboard = clipboard, pty = pty, parser = parser, recovery = recovery })
      mouse = active_session.mouse
      mouse_generation = state.modes.mouse_generation
      active_session.mouse_generation = mouse_generation
      selection_pointer = active_session.selection_pointer
    else
      terminal = new_terminal(columns, rows)
      state = VTInternal.state(terminal)
      pty = spawn_child(options.command, columns, rows)
      parser = VTInternal.parser(terminal)
      recovery = Recovery.new()
      renderer = Renderer.new(context, font, state, render_options)
      metrics = Metrics.new(context, font, state, { clipboard = clipboard, pty = pty, parser = parser, recovery = recovery })
      mouse = Mouse.new()
      mouse_generation = state.modes.mouse_generation
      selection_pointer = SelectionPointer.new()
      active_session = {
        metrics = metrics,
        mouse = mouse,
        mouse_generation = mouse_generation,
        pty = pty,
        recovery = recovery,
        renderer = renderer,
        selection_pointer = selection_pointer,
        terminal = terminal,
      }
    end
    if options.record then
      recorder = Replay.Recorder.new(options.record)
      recorder:resize(columns, rows)
    end
    local last_title
    local max_frames = number_from_env("KIWI_MAX_FRAMES", 0)
    local max_seconds = number_from_env("KIWI_MAX_SECONDS", 0)
    local simulated_device_loss_frame = number_from_env("KIWI_SIMULATE_DEVICE_LOSS_FRAME", 0)
    local simulated_device_loss = false
    local soak_seconds = number_from_env("KIWI_DEVICE_SOAK_SECONDS", 0)
    local soak = soak_seconds > 0 and DeviceSoak.Lifecycle.new(window, { seconds = soak_seconds }) or nil
    local pty_read_budget = number_from_env("KIWI_PTY_READ_BUDGET", 4 * 1024)
    local kitty_transfer_read_budget = number_from_env("KIWI_KITTY_TRANSFER_READ_BUDGET", 256 * 1024)
    local kitty_graphics_report = os.getenv("KIWI_KITTY_GRAPHICS_REPORT") == "1"
    local kitty_transfer_started_at
    local kitty_first_visible_at
    local kitty_first_visible_frame
    local pacing_report = os.getenv("KIWI_PACING_REPORT")
    local pacing = pacing_report and Pacing.new({
      sample_limit = number_from_env("KIWI_PACING_SAMPLES", 240),
      warmup_frames = number_from_env("KIWI_PACING_WARMUP_FRAMES", 30),
      pty_read_budget = pty_read_budget,
    }) or nil
    local power_report = os.getenv("KIWI_POWER_REPORT")
    local power = power_report and Power.new({ active_poll_seconds = 0.050, minimized_poll_seconds = 0.250 }) or nil
    local power_synthetic_input = power and os.getenv("KIWI_POWER_SYNTHETIC_INPUT") == "1"
    local synthetic_input_sent = false
    local hyperlink_pointer = HyperlinkPointer.new(hyperlink, glfw)
    local configuration_reload_requested = false
    workspace = Workspace.new()
    assert(workspace:new_tab(active_session))

    destroy_session = function(session)
      if session.closed then return end
      session.closed = true
      if session.renderer then
        session.renderer:destroy()
        session.renderer = nil
      end
      session.pty:shutdown()
      session.terminal:close()
    end

    local function bind_active_session(session)
      if composition ~= nil and state ~= nil and state ~= VTInternal.state(session.terminal) then
        state.ime_preedit = nil
        composition:leave()
        composition:enter()
      end
      active_session = session
      terminal = session.terminal
      state = VTInternal.state(terminal)
      pty = session.pty
      renderer = session.renderer
      metrics = session.metrics
      mouse = session.mouse
      mouse_generation = session.mouse_generation
      recovery = session.recovery
      selection_pointer = session.selection_pointer
    end

    local function rebuild_session_renderer(session)
      if session.renderer then session.renderer:destroy() end
      session.renderer = Renderer.new(context, font, VTInternal.state(session.terminal), render_options)
      session.renderer:invalidate("configuration")
      if session == active_session then renderer = session.renderer end
    end

    local function refresh_workspace_layout()
      local columns, rows = dimensions(window, font)
      if columns == nil then return nil, "zero-sized drawable" end
      workspace_columns = columns
      workspace_rows = rows
      local layout, reason = workspace:layout(columns, rows)
      if layout == nil then return nil, reason end
      pane_entries = {}
      pane_layouts = {}
      for _, placement in ipairs(layout) do
        local pane = assert(workspace.panes[placement.pane_id], "workspace layout references an unknown pane")
        local session = pane.session
        local session_state = VTInternal.state(session.terminal)
        session.terminal:set_cell_metrics(font.cell_width, font.cell_height)
        if session_state.columns ~= placement.width or session_state.rows ~= placement.height then
          if session.renderer then
            session.renderer:destroy()
            session.renderer = nil
          end
          session.terminal:resize(placement.width, placement.height)
          session.pty:resize(placement.width, placement.height)
          if session == active_session and recorder then recorder:resize(placement.width, placement.height) end
        end
        if session.renderer == nil then rebuild_session_renderer(session) end
        local viewport = Compositor.viewport(placement, font.cell_width, font.cell_height)
        pane_layouts[pane.id] = { grid = placement, viewport = viewport }
        pane_entries[#pane_entries + 1] = { model = VTInternal.state(session.terminal), renderer = session.renderer, viewport = viewport }
      end
      local active_pane = assert(workspace:active_pane(), "workspace has no active pane")
      bind_active_session(active_pane.session)
      return columns, rows
    end

    local function activate_pane(id)
      local pane = id and workspace.panes[id] or workspace:active_pane()
      if pane == nil then return nil, "unknown-pane" end
      assert(workspace:focus_pane(pane.id))
      bind_active_session(pane.session)
      renderer:invalidate("terminal")
      options.application:mark_layout_dirty()
      return true
    end

    local function new_session(columns, rows, command)
      local session_terminal = new_terminal(columns, rows)
      local new_state = VTInternal.state(session_terminal)
      local new_pty = spawn_child(command == false and nil or command or options.command, columns, rows)
      local new_recovery = Recovery.new()
      return {
        metrics = Metrics.new(context, font, new_state, { clipboard = clipboard, pty = new_pty, parser = VTInternal.parser(session_terminal), recovery = new_recovery }),
        mouse = Mouse.new(),
        mouse_generation = new_state.modes.mouse_generation,
        pty = new_pty,
        recovery = new_recovery,
        renderer = nil,
        selection_pointer = SelectionPointer.new(),
        terminal = session_terminal,
      }
    end

    if options.restored_workspace then
      destroy_session(active_session)
      workspace = Workspace.restore(options.restored_workspace, function()
        return new_session(columns, rows, false)
      end)
    end

    local function focus_next_tab()
      local current = workspace:active_tab()
      if current == nil or workspace:tab_count() < 2 then return false end
      for index, tab in ipairs(workspace.tabs) do
        if tab.id == current.id then
          local next_tab = workspace.tabs[index % #workspace.tabs + 1]
          assert(workspace:focus_tab(next_tab.id))
          assert(refresh_workspace_layout())
          return activate_pane(next_tab.active_pane_id)
        end
      end
      return false
    end

    local function create_tab()
      if recorder then return nil, "tabs are unavailable while --record is active" end
      local session = new_session(state.columns, state.rows)
      local pane, reason = workspace:new_tab(session)
      if pane == nil then
        destroy_session(session)
        return nil, reason
      end
      assert(refresh_workspace_layout())
      return activate_pane(pane.id)
    end

    local function create_split(direction)
      if recorder then return nil, "splits are unavailable while --record is active" end
      local session = new_session(1, 1)
      local pane, reason = workspace:split(direction, session)
      if pane == nil then
        destroy_session(session)
        return nil, reason
      end
      assert(refresh_workspace_layout())
      return activate_pane(pane.id)
    end

    local function close_active_tab()
      if workspace:tab_count() == 1 then
        window:request_close()
        return true
      end
      local tab = assert(workspace:active_tab())
      local closing = {}
      for _, pane in pairs(workspace.panes) do
        if pane.tab_id == tab.id then closing[#closing + 1] = pane.session end
      end
      assert(workspace:close_tab(tab.id))
      for _, session in ipairs(closing) do destroy_session(session) end
      assert(refresh_workspace_layout())
      return activate_pane(assert(workspace:active_pane()).id)
    end

    local function close_active_pane()
      local pane = assert(workspace:active_pane())
      local closed, reason = workspace:close_pane(pane.id)
      if closed == nil and reason == "last-pane" then return close_active_tab() end
      if closed == nil then return nil, reason end
      destroy_session(pane.session)
      assert(refresh_workspace_layout())
      return activate_pane(assert(workspace:active_pane()).id)
    end

    assert(refresh_workspace_layout())
    if options.workspace_smoke then assert(create_split("vertical")) end
    if options.layout_restored then
      io.stdout:write(string.format("Kiwi layout restored: tabs=%d panes=%d; each pane received a fresh shell session.\n", workspace:tab_count(), workspace:pane_count()))
    end

    local pending_transfer
    local transferred_away
    local function rebind_session_to_this_window(session)
      if session.renderer then
        session.renderer:destroy()
        session.renderer = nil
      end
      local session_state = VTInternal.state(session.terminal)
      session.metrics.context = context
      session.metrics.font = font
      session.metrics.model = session_state
      session.metrics:set_runtime({ clipboard = clipboard, pty = session.pty, parser = VTInternal.parser(session.terminal), recovery = session.recovery })
      session.mouse_generation = session_state.modes.mouse_generation
      session_state:mark_all_dirty()
    end

    local function begin_transfer()
      if pending_transfer then return nil, "transfer-pending" end
      local pane = workspace:active_pane()
      if pane == nil then return nil, "no-active-pane" end
      local detached, reason = workspace:detach_pane(pane.id)
      if detached == nil then return nil, reason end
      pending_transfer = detached.session
      if workspace:tab_count() > 0 then
        assert(refresh_workspace_layout())
        assert(activate_pane(assert(workspace:active_pane()).id))
      else
        pane_entries = {}
        pane_layouts = {}
      end
      return pending_transfer
    end

    local function restore_transfer(session)
      if pending_transfer ~= session then return nil, "unknown-transfer" end
      local pane, reason = workspace:adopt_tab(session)
      if pane == nil then return nil, reason end
      pending_transfer = nil
      rebind_session_to_this_window(session)
      assert(refresh_workspace_layout())
      return activate_pane(pane.id)
    end

    local function complete_transfer(session)
      if pending_transfer ~= session then return nil, "unknown-transfer" end
      pending_transfer = nil
      if workspace:tab_count() == 0 then
        transferred_away = session
        assert(options.application:unregister_controller(options.controller_id))
        window:request_close()
        return true
      end
      assert(refresh_workspace_layout())
      return activate_pane(assert(workspace:active_pane()).id)
    end

    local function accept_transfer(session)
      local pane, reason = workspace:adopt_tab(session)
      if pane == nil then return nil, reason end
      rebind_session_to_this_window(session)
      assert(refresh_workspace_layout())
      assert(activate_pane(pane.id))
      return true
    end

    assert(options.application:register_controller(options.controller_id, {
      accept_transfer = accept_transfer,
      begin_transfer = begin_transfer,
      complete_transfer = complete_transfer,
      destroy_session = destroy_session,
      new_session = function() return new_session(1, 1, false) end,
      restore_transfer = restore_transfer,
      snapshot = function()
        return { geometry = window:geometry(), workspace = workspace:snapshot() }
      end,
    }))
    local transfer_confirmation_pending = options.transfer_source_id ~= nil
    local last_geometry = window:geometry()

    local function capture_geometry_change()
      local current = window:geometry()
      if current.x ~= last_geometry.x or current.y ~= last_geometry.y or current.width ~= last_geometry.width or current.height ~= last_geometry.height then
        last_geometry = current
        options.application:mark_layout_dirty()
      end
    end

    local accessibility_projection = AtspiProjection.new()
    local window_focused = true
    local accessibility_reason
    accessibility, accessibility_reason = host.accessibility_new and host.accessibility_new(window) or nil, "unavailable for this host"
    if accessibility == nil and os.getenv("KIWI_ACCESSIBILITY_DIAGNOSTICS") == "1" then
      io.stderr:write("Kiwi accessibility: unavailable: ", accessibility_reason, "\n")
    end

    local function sync_accessibility()
      if accessibility == nil then return end
      local projection = accessibility_projection:project(VTInternal.state(active_session.terminal))
      local updated, reason = accessibility:update(projection, last_title or default_title, window_focused)
      if updated then
        accessibility:poll()
        return
      end
      accessibility:destroy()
      accessibility = nil
      if os.getenv("KIWI_ACCESSIBILITY_DIAGNOSTICS") == "1" then
        io.stderr:write("Kiwi accessibility: disabled after provider failure: ", reason, "\n")
      end
    end

    local update_automation_action_handler

    local function apply_configuration(reloaded, path)
      if reloaded.ambiguous_width ~= configuration.ambiguous_width or reloaded.scrollback_limit ~= configuration.scrollback_limit then
        return nil, "ambiguous-width and scrollback-limit require a new terminal session"
      end
      local candidate_actions = ProductActions.new(reloaded.keybindings, glfw)
      reloaded.host_effects = require("kiwi.app.host_effects").new(reloaded, host, window)
      local previous_font = font
      local font_changed = reloaded.font_size ~= configuration.font_size
        or reloaded.font_path ~= configuration.font_path
        or reloaded.font_family ~= configuration.font_family
        or reloaded.ligatures ~= configuration.ligatures
        or reloaded.contextual_alternates ~= configuration.contextual_alternates
      local candidate_font = font_changed and new_font(window, reloaded) or font
      configuration = reloaded
      configuration_path = path
      product_actions = candidate_actions
      render_options = renderer_options(options, configuration)
      for _, pane in pairs(workspace.panes) do
        VTInternal.state(pane.session.terminal):configure_palette({
          foreground = configuration.foreground,
          background = configuration.background,
          palette = configuration.palette,
        })
        VTInternal.state(pane.session.terminal):configure_osc52_write(configuration.osc52_write)
      end
      if font_changed then
        font = candidate_font
        for _, pane in pairs(workspace.panes) do pane.session.metrics.font = font end
      end
      for _, pane in pairs(workspace.panes) do
        local session = pane.session
        if session.renderer then
          session.renderer:destroy()
          session.renderer = nil
        end
        VTInternal.state(session.terminal):mark_all_dirty()
      end
      local refreshed, reason = refresh_workspace_layout()
      if not refreshed then return nil, reason end
      if font_changed then previous_font:destroy() end
      if update_automation_action_handler then update_automation_action_handler() end
      return true
    end

    local function recreate_gpu()
      for _, pane in pairs(workspace.panes) do
        local session = pane.session
        if session.renderer then
          session.renderer:destroy()
          session.renderer = nil
        end
      end
      if context then
        context:destroy()
        context = nil
      end
      context = Context.new(host, window, context_options)
      compositor = Compositor.new(context)
      for _, pane in pairs(workspace.panes) do pane.session.metrics.context = context end
      assert(refresh_workspace_layout())
    end

    local function handle_render_failure(reason)
      local activity = renderer and renderer.pass_registry and renderer.pass_registry:activity_snapshot() or nil
      local diagnostic = recovery:decide(reason, context, activity)
      io.stderr:write("Kiwi GPU recovery: ", Recovery.format(diagnostic, recovery.max_device_retries), "\n")
      if diagnostic.action == "retry-device" then
        recreate_gpu()
      elseif diagnostic.action == "retry-surface" then
        context.window.resized = true
      elseif diagnostic.action == "exit" then
        error("Kiwi GPU failure: " .. Recovery.format(diagnostic, recovery.max_device_retries))
      end
    end

    local function enqueue_input(bytes, synthetic)
      if pacing then pacing:input(window:time()) end
      if power then power:input(synthetic) end
      if recorder then recorder:input(bytes) end
      pty:enqueue(bytes)
    end

    local function report_clipboard_failure(operation, status)
      io.stderr:write("Kiwi clipboard ", operation, " rejected: ", status:gsub("_", " "), "\n")
    end

    local function report_search_status(status)
      if status ~= "matches" and status ~= "query" and status ~= "inactive" then
        io.stderr:write("Kiwi search: ", status:gsub("-", " "), "\n")
      end
    end

    local function report_hyperlink_failure(status)
      if status ~= "no-link" then io.stderr:write("Kiwi hyperlink activation rejected: ", (status or "unavailable"):gsub("-", " "), "\n") end
    end

    local function report_region_status(status)
      if status ~= "navigated" then io.stderr:write("Kiwi regions: ", status:gsub("-", " "), "\n") end
    end

    composition = Composition.new()
    composition:enter()

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
      renderer:invalidate("terminal")
    end

    local function apply_preedit(text, selection_start, selection_end)
      if not composition.focused then composition:enter() end
      local accepted, status = composition:offer_preedit(text, selection_start, selection_end)
      if not accepted then
        io.stderr:write("Kiwi IME preedit rejected: ", status, "\n")
        return
      end
      local update = assert(composition:done())
      update_preedit_overlay(update)
    end

    local function apply_commit(text)
      if not composition.focused then composition:enter() end
      local accepted, status = composition:offer_preedit("", 0, 0)
      if accepted then update_preedit_overlay(assert(composition:done())) end
      accepted, status = composition:offer_commit(text)
      if not accepted then
        io.stderr:write("Kiwi IME commit rejected: ", status, "\n")
        return
      end
      local update = assert(composition:done())
      update_preedit_overlay(update)
      return update.commit
    end

    local function update_search_title()
      local search = state:search_view()
      local title = search.editing and search.visible and "Kiwi search: " .. search.query or state.title or default_title
      if title ~= last_title then
        window:set_title(title)
        last_title = title
      end
    end

    local function handle_committed_text(text)
      if text == nil or #text == 0 then return end
      local search = state:search_view()
      if search.editing and search.visible then
        local appended, status = state:search_append(text)
        if not appended then report_search_status(status) end
        renderer:invalidate("search")
      else
        enqueue_input(text)
      end
    end

    local function handle_search_key(key, action)
      local search = state:search_view()
      if not search.editing or not search.visible then return false end
      if key == glfw.key_escape then
        if action == glfw.press then state:clear_search() end
        return action == glfw.press or action == glfw.repeat_action
      end
      if key == glfw.key_backspace then
        if action == glfw.press or action == glfw.repeat_action then state:search_backspace() end
        return action == glfw.press or action == glfw.repeat_action
      end
      if key == glfw.key_enter then
        if action == glfw.press then
          local _, status = state:search_submit("forward")
          report_search_status(status)
        end
        return action == glfw.press or action == glfw.repeat_action
      end
      return false
    end

    local action_dispatcher = require("kiwi.app.product_action_dispatcher").new({
      active_session = function() return active_session end,
      application = options.application,
      close_active_pane = close_active_pane,
      configuration = function() return configuration end,
      configuration_path = function() return configuration_path end,
      controller_id = options.controller_id,
      create_split = create_split,
      create_tab = create_tab,
      explicit_configuration_path = options.config,
      focus_next_tab = focus_next_tab,
      host = host,
      report = function(message) io.stderr:write(message, "\n") end,
      request_configuration_reload = function() configuration_reload_requested = true end,
      session_move_smoke_requester = options.session_move_smoke_requester,
      set_configuration_path = function(path)
        configuration_path = path
        configuration.path = path
      end,
      window = window,
    })

    local function handle_product_action(product_action)
      return action_dispatcher:handle(product_action)
    end

    local function handle_workspace_key(key, action, modifiers)
      if bit.band(state.modes.keyboard_flags, 8) ~= 0 then
        product_actions:reset_sequence()
        return false
      end
      if action ~= glfw.press then return false end
      local product_action, sequence_status = product_actions:lookup(key, modifiers, window:time())
      local handled = product_action ~= nil and handle_product_action(product_action)
      return handled or sequence_status == "pending"
    end

    local function handle_native_product_action(product_action)
      local handled, layout_changed = handle_product_action(product_action)
      if handled and layout_changed then options.application:mark_layout_dirty() end
      return handled
    end

    local product_action_handler_enabled = false
    if host.set_product_action_handler then
      local menu_enabled, menu_reason = host.set_product_action_handler(window, handle_native_product_action)
      product_action_handler_enabled = menu_enabled == true
      if not menu_enabled then io.stderr:write("Kiwi native menu unavailable: ", menu_reason or "unknown error", "\n") end
    end

    local automation_action_handler_enabled = false
    update_automation_action_handler = function()
      if not host.set_automation_action_handler then return false end
      if configuration.macos_applescript and not automation_action_handler_enabled then
        local enabled, reason = host.set_automation_action_handler(window, handle_native_product_action)
        automation_action_handler_enabled = enabled == true
        if not enabled then io.stderr:write("Kiwi native automation unavailable: ", reason or "unknown error", "\n") end
      elseif not configuration.macos_applescript and automation_action_handler_enabled then
        host.remove_automation_action_handler(window)
        automation_action_handler_enabled = false
      end
      return automation_action_handler_enabled
    end
    update_automation_action_handler()

    if options.menu_smoke then
      assert(product_action_handler_enabled and host.invoke_product_action_smoke, "--menu-smoke needs the native product-action bridge")
      local tabs_before = workspace:tab_count()
      local invoked, reason = host.invoke_product_action_smoke(window, "new-tab")
      assert(invoked, "native product-menu smoke could not invoke New Tab: " .. tostring(reason))
      assert(workspace:tab_count() == tabs_before + 1, "native product-menu smoke did not create a tab through the host controller")
      options.application.menu_smoke_reported = true
    end
    if options.automation_smoke then
      assert(automation_action_handler_enabled and host.invoke_automation_action_smoke, "--automation-smoke needs the native Apple-event action bridge")
      local tabs_before = workspace:tab_count()
      local invoked, reason = host.invoke_automation_action_smoke(window, "new-tab")
      assert(invoked, "native Apple-event smoke could not invoke New Tab: " .. tostring(reason))
      assert(workspace:tab_count() == tabs_before + 1, "native Apple-event smoke did not create a tab through the live controller")
      options.application.automation_smoke_reported = true
    end
    if options.palette_smoke then
      assert(host.show_command_palette and host.invoke_command_palette_smoke, "--palette-smoke needs the native command-palette bridge")
      local tabs_before = workspace:tab_count()
      local palette_handled = handle_product_action("command-palette")
      assert(palette_handled)
      local invoked, reason = host.invoke_command_palette_smoke(window)
      assert(invoked, "native command-palette smoke could not select its first action: " .. tostring(reason))
      assert(workspace:tab_count() == tabs_before + 1, "native command-palette smoke did not create a tab through the live controller")
      options.application.palette_smoke_reported = true
    end

    local pointer_pane_id
    local function pointer_pane(event)
      local pane
      local placement
      if event.kind == "button" and event.action == "press" then
        local column = math.floor(event.x * (font.content_scale or 1) / font.cell_width)
        local row = math.floor(event.y * (font.content_scale or 1) / font.cell_height)
        pane, placement = workspace:pane_at(workspace_columns, workspace_rows, column, row)
        if pane then
          pointer_pane_id = pane.id
          activate_pane(pane.id)
        end
      elseif pointer_pane_id then
        pane = workspace.panes[pointer_pane_id]
        placement = pane and pane_layouts[pane.id] and pane_layouts[pane.id].grid or nil
      else
        local column = math.floor(event.x * (font.content_scale or 1) / font.cell_width)
        local row = math.floor(event.y * (font.content_scale or 1) / font.cell_height)
        pane, placement = workspace:pane_at(workspace_columns, workspace_rows, column, row)
      end
      if pane == nil or placement == nil then return nil end
      event.x = event.x - placement.x * font.cell_width / (font.content_scale or 1)
      event.y = event.y - placement.y * font.cell_height / (font.content_scale or 1)
      local scale = font.content_scale or 1
      local pixel_width = math.max(1, math.floor(placement.width * font.cell_width + 0.5))
      local pixel_height = math.max(1, math.floor(placement.height * font.cell_height + 0.5))
      event.pixel_x = math.max(1, math.min(pixel_width, math.floor(event.x * scale) + 1))
      event.pixel_y = math.max(1, math.min(pixel_height, math.floor(event.y * scale) + 1))
      return pane
    end

    window:set_input_handlers(function(codepoints, key_event)
      if key_event then
        apply_commit("")
        local encoded = Keyboard.key(key_event.key, key_event.action, key_event.modifiers, state.modes, glfw, {
          associated_text = codepoints,
          layout_key = key_event.variants and key_event.variants.layout_key,
          shifted_key = key_event.variants and key_event.variants.shifted_key,
          base_key = key_event.variants and key_event.variants.base_key,
        })
        if encoded and encoded.bytes then enqueue_input(encoded.bytes) end
        return
      end
      local text = Keyboard.text_sequence(codepoints, state.modes)
      handle_committed_text(text)
    end, function(key, action, modifiers, variants)
      if handle_workspace_key(key, action, modifiers) then
        options.application:mark_layout_dirty()
        return { handled = true, suppress_text = true }
      end
      if handle_search_key(key, action) then
        renderer:invalidate("search")
        return { handled = true, suppress_text = true }
      end
      if Keyboard.should_defer_text(key, action, modifiers, state.modes, glfw) then
        return { handled = true, defer_text = true }
      end
      local encoded = Keyboard.key(key, action, modifiers, state.modes, glfw, variants)
      if not encoded then
        return nil
      end
      if encoded.local_action == "scroll_up" then
        state:scroll_history(math.max(1, state.rows - 1))
        renderer:invalidate("terminal")
      elseif encoded.local_action == "scroll_down" then
        state:scroll_history(-math.max(1, state.rows - 1))
        renderer:invalidate("terminal")
      elseif encoded.local_action and encoded.local_action:match("^region_") then
        local direction, role = encoded.local_action:match("^region_([^_]+)_([^_]+)$")
        local _, status = state:navigate_command_region(role, direction == "next" and "forward" or "backward")
        report_region_status(status)
        renderer:invalidate("terminal")
      elseif encoded.local_action == "copy" then
        local copied, status = clipboard:copy(state)
        if not copied then report_clipboard_failure("copy", status) end
      elseif encoded.local_action == "paste" then
        local bytes, status = clipboard:paste(state)
        if bytes then
          enqueue_input(bytes)
        elseif status ~= "empty" then
          report_clipboard_failure("paste", status)
        end
      elseif encoded.local_action == "search_begin" then
        state:search_begin("forward")
        renderer:invalidate("search")
      elseif encoded.local_action == "search_next" or encoded.local_action == "search_previous" then
        local direction = encoded.local_action == "search_next" and "forward" or "backward"
        local _, status
        local search = state:search_view()
        if search.editing and search.visible then
          _, status = state:search_submit(direction)
        else
          _, status = state:search_navigate(direction)
        end
        report_search_status(status)
        renderer:invalidate("search")
      elseif encoded.local_action == "open_hyperlink" then
        local opened, status = hyperlink:activate(state:hyperlink_at_cursor())
        if not opened then report_hyperlink_failure(status) end
      elseif encoded.bytes then
        enqueue_input(encoded.bytes)
      end
      return { handled = true, suppress_text = encoded.suppress_text }
    end, function(event)
      local pane = pointer_pane(event)
      if pane == nil then return end
      event.selection_column, event.selection_row = SelectionPointer.cell_position(event.x, event.y, font.content_scale or 1, font.cell_width, font.cell_height, state.columns, state.rows)
      event.column = event.selection_column + 1
      event.row = event.selection_row + 1
      local hyperlink_handled, hyperlink_opened, hyperlink_status = hyperlink_pointer:handle(event, state, state.modes)
      if hyperlink_handled and not hyperlink_opened then report_hyperlink_failure(hyperlink_status) end
      local selection_handled, selection_changed = false, false
      if not hyperlink_handled then selection_handled, selection_changed = selection_pointer:handle(event, state, state.modes) end
      if selection_changed then renderer:invalidate("selection") end
      local encoded
      if not hyperlink_handled and not selection_handled and event.kind == "button" then
        encoded = mouse:button(event, state:input_modes())
      elseif not hyperlink_handled and not selection_handled and event.kind == "motion" then
        encoded = mouse:motion(event, state:input_modes())
      elseif not hyperlink_handled and not selection_handled and event.kind == "wheel" then
        encoded = mouse:wheel(event, state:input_modes())
      end
      if encoded then enqueue_input(encoded) end
      if event.kind == "button" and event.action == "release" then pointer_pane_id = nil end
    end, function(focused)
      window_focused = focused
      if not focused then
        product_actions:reset_sequence()
        selection_pointer:reset()
        state.ime_preedit = nil
        composition:leave()
        if renderer then renderer:invalidate("terminal") end
      else
        composition:enter()
      end
      local encoded = mouse:focus(focused, state:input_modes())
      if encoded then enqueue_input(encoded) end
    end)
    if host.enable_text_input then
      local enabled, reason = host.enable_text_input(window, apply_preedit, function(text)
        local committed = apply_commit(text)
        local codepoints = codepoints_from_utf8(committed)
        handle_committed_text(codepoints and Keyboard.text_sequence(codepoints, state.modes) or nil)
      end)
      if not enabled then io.stderr:write("Kiwi IME: unavailable: ", reason, "\n") end
    end
    local function sync_text_input_caret()
      local pane = workspace:active_pane()
      local layout = pane and pane_layouts[pane.id]
      if layout == nil then return end
      local scale = font.content_scale or 1
      local cursor = state.cursor
      if not host.set_text_input_caret then return end
      host.set_text_input_caret(window,
        (layout.grid.x + cursor.column) * font.cell_width / scale,
        (layout.grid.y + cursor.row) * font.cell_height / scale,
        math.max(1, font.cell_width / scale),
        math.max(1, font.cell_height / scale)
      )
    end
    if transfer_confirmation_pending then
      if options.session_move_smoke then
        assert(options.moved_session.session_move_smoke_source_id == options.transfer_source_id, "session-move smoke lost the transferred session identity")
        assert(options.moved_session.pty == pty, "session-move smoke replaced the transferred PTY")
        assert(host.live_count() == 2, "session-move smoke did not retain both native windows during handoff")
        options.application.session_move_smoke_reported = true
      end
      assert(options.application:confirm_transfer(options.controller_id))
    end
    if options.multi_window_smoke_requester then
      assert(handle_workspace_key(string.byte("N"), glfw.press, glfw.mod_control + glfw.mod_shift))
    end
    if options.session_move_smoke_requester then
      assert(handle_workspace_key(string.byte("M"), glfw.press, glfw.mod_control + glfw.mod_shift))
    end
    if options.key_sequence_smoke then
      local tabs_before = workspace:tab_count()
      assert(handle_workspace_key(string.byte("A"), glfw.press, glfw.mod_control), "key-sequence smoke did not consume the configured prefix")
      assert(workspace:tab_count() == tabs_before, "key-sequence smoke ran an action before the sequence completed")
      assert(not handle_workspace_key(string.byte("A"), glfw.release, glfw.mod_control), "key-sequence smoke treated a key release as a workspace action")
      assert(handle_workspace_key(string.byte("N"), glfw.press, 0), "key-sequence smoke did not complete the configured sequence")
      assert(workspace:tab_count() == tabs_before + 1, "key-sequence smoke did not create a tab through the live controller")
      options.application.key_sequence_smoke_reported = true
    end

    local child_label = options.moved_session and "moved-session" or options.command and options.command[1] or Pty.default_command()[1]
    io.stdout:write(string.format("Kiwi M2: Unicode=17.0 TERM=xterm-kiwi child=%s grid=%dx%d primary=%s\n", child_label, columns, rows, font.font_path))
    if options.session_move_smoke and options.application.session_move_smoke_reported then
      io.stdout:write("Kiwi session-move smoke passed: one live PTY moved between native windows in this application process.\n")
    end
    if options.menu_smoke and options.application.menu_smoke_reported then
      io.stdout:write("Kiwi native product-menu smoke passed: New Tab reached the live workspace controller through the native menu bridge.\n")
    end
    if options.palette_smoke and options.application.palette_smoke_reported then
      io.stdout:write("Kiwi native command-palette smoke passed: a searchable palette selected New Tab through the live workspace controller.\n")
    end
    if options.automation_smoke and options.application.automation_smoke_reported then
      io.stdout:write("Kiwi native Apple-event smoke passed: a bounded New Tab command reached the live workspace controller.\n")
    end
    if options.key_sequence_smoke and options.application.key_sequence_smoke_reported then
      io.stdout:write("Kiwi key-sequence smoke passed: a press/release prefix created a tab through the live workspace controller.\n")
    end
    while not window:should_close() do
      local now = window:time()
      if max_seconds > 0 and now - started_at >= max_seconds then break end
      local deadline = compositor:next_render_deadline(pane_entries)
      local maximum_wait = window.minimized and 0.250 or 0.050
      for _, pane in pairs(workspace.panes) do
        if VTInternal.state(pane.session.terminal).kitty_graphics.transfer ~= nil then
          maximum_wait = math.min(maximum_wait, 0.001)
          break
        end
      end
      local requested_wait = deadline and now < deadline and math.min(deadline - now, maximum_wait) or maximum_wait
      host.await_events(options.application, window, requested_wait)
      while pending_transfer and not window:should_close() do
        host.await_events(options.application, window, 0)
      end
      if window:should_close() then break end
      capture_geometry_change()
      if options.multi_window_smoke and not options.application.multi_window_smoke_reported then
        assert(host.live_count() == 2, "same-process multi-window smoke did not retain two native windows")
        options.application.multi_window_smoke_reported = true
        io.stdout:write("Kiwi same-process multi-window smoke passed: two native window controllers share this application process.\n")
      end
      now = window:time()
      local observed_appearance = host.system_appearance and host.system_appearance(window) or nil
      if configuration.theme_mode == "system" and observed_appearance ~= nil and observed_appearance ~= system_appearance then
        system_appearance = observed_appearance
        configuration_reload_requested = true
      end
      if configuration_reload_requested then
        configuration_reload_requested = false
        local loaded, reloaded_or_error, path = pcall(load_configuration)
        if not loaded then
          io.stderr:write("Kiwi configuration reload rejected: ", tostring(reloaded_or_error), "\n")
        else
          local applied, reason = apply_configuration(reloaded_or_error, path)
          if not applied then
            io.stderr:write("Kiwi configuration reload rejected: ", reason, "\n")
          else
            io.stdout:write("Kiwi configuration reloaded", configuration_path and ": " .. configuration_path or " (defaults)", "\n")
          end
        end
      end
      if power then
        local power_state = window.minimized and "minimized" or compositor:needs_render(pane_entries, now) and "active" or "idle"
        power:observe(now, power_state, requested_wait)
      end
      if soak and soak:step(now) then window:request_close() end
      if power_synthetic_input and not synthetic_input_sent then
        synthetic_input_sent = true
        enqueue_input("power-synthetic-input\n", true)
      end

      local function consume_session_output(session, output)
        if #output == 0 then return end
        if session == active_session then
          if pacing then pacing:output(now) end
          if power then power:output() end
          if recorder then recorder:output(output) end
        end
        local session_state = VTInternal.state(session.terminal)
        local image_count = session_state.kitty_graphics:image_count()
        local placement_count = #session_state.kitty_placements.placements
        session.terminal:write(output)
        session_state = VTInternal.state(session.terminal)
        if kitty_graphics_report and kitty_transfer_started_at == nil and session_state.kitty_graphics.transfer ~= nil then
          kitty_transfer_started_at = now
        end
        if session_state.modes.mouse_generation ~= session.mouse_generation then
          session.mouse:reset()
          session.selection_pointer:reset()
          session.mouse_generation = session_state.modes.mouse_generation
          if session == active_session then mouse_generation = session.mouse_generation end
        end
        local kitty_graphics_changed = image_count ~= session_state.kitty_graphics:image_count()
          or placement_count ~= #session_state.kitty_placements.placements
        if session.renderer and (session_state.damage.dirty_count > 0 or kitty_graphics_changed) then
          session.renderer:invalidate(kitty_graphics_changed and "kitty_images" or "terminal")
        end
      end

      local panes = {}
      for _, pane in pairs(workspace.panes) do panes[#panes + 1] = pane end
      local per_session_read_budget = math.max(1, math.floor(pty_read_budget / math.max(1, #panes)))
      for _, pane in ipairs(panes) do
        local session = pane.session
        consume_session_output(session, session.pty:read_available(per_session_read_budget))
      end

      local per_session_kitty_transfer_budget = math.max(1, math.floor(kitty_transfer_read_budget / math.max(1, #panes)))
      for _, pane in ipairs(panes) do
        local session = pane.session
        if VTInternal.state(session.terminal).kitty_graphics.transfer ~= nil then
          consume_session_output(session, session.pty:read_available(per_session_kitty_transfer_budget))
        end
      end

      for _, pane in pairs(workspace.panes) do
        local session = pane.session
        local responses = session.terminal:pop_responses()
        if #responses > 0 then session.pty:enqueue(table.concat(responses)) end
        for _, effect in ipairs(session.terminal:pop_effects()) do
          if effect.kind == "clipboard_write_requested" then
            local written, status = clipboard:write_osc52(effect.value.text)
            if not written then io.stderr:write("Kiwi OSC 52 clipboard write rejected: ", status, "\n") end
          else
            local consumed, status, first_report = configuration.host_effects:consume(effect)
            if consumed and status ~= "submitted" and first_report then
              io.stderr:write("Kiwi OSC 9 ", effect.kind == "notification_requested" and "notification" or "progress", " ignored: ", status, "\n")
            end
          end
        end
        session.pty:flush()
        session.child_status = session.pty:poll_exit()
      end
      local child_status = active_session.child_status
      update_search_title()
      sync_accessibility()
      sync_text_input_caret()

      for _, entry in ipairs(pane_entries) do
        if entry.model.kitty_graphics:advance(now) then entry.renderer:invalidate("kitty_images") end
      end

      do
        local scale_changed = math.abs(content_scale(window) - font.content_scale) > 0.001
        local drawable_width, drawable_height = window:drawable_size()
        local surface_size_changed = drawable_width > 0 and drawable_height > 0
          and (drawable_width ~= context.width or drawable_height ~= context.height)
        local previous_font
        if scale_changed then
          previous_font = font
          font = new_font(window, configuration)
          window.resized = true
          for _, pane in pairs(workspace.panes) do
            local session = pane.session
            session.metrics.font = font
            if session.renderer then
              session.renderer:destroy()
              session.renderer = nil
            end
          end
        end
        local new_columns, new_rows = dimensions(window, font)
        if (window.resized or surface_size_changed) and not context:configure_surface() then
          if previous_font then
            previous_font:destroy()
            previous_font = nil
          end
        elseif new_columns and (scale_changed or renderer == nil or new_columns ~= workspace_columns or new_rows ~= workspace_rows) then
          assert(refresh_workspace_layout())
          if previous_font then
            previous_font:destroy()
            previous_font = nil
          end
        elseif previous_font then
          assert(refresh_workspace_layout())
          previous_font:destroy()
          previous_font = nil
        end
        if not window.minimized then
          if window:take_shader_reload_request() then
            for _, entry in ipairs(pane_entries) do
              local reloaded, message = entry.renderer:reload_shaders(true)
              if entry.renderer == renderer then report_shader_reload(reloaded, message) end
              if reloaded then entry.renderer:invalidate("configuration") end
            end
          else
            for _, entry in ipairs(pane_entries) do
              if entry.renderer:shader_reload_enabled() then
                local reloaded, message = entry.renderer:poll_shader_reload(now)
                if entry.renderer == renderer then report_shader_reload(reloaded, message) end
              end
            end
          end
        end
        if compositor:needs_render(pane_entries, now) and compositor:can_present(pane_entries) then
          local frame_start = now
          local invalidation = (pacing or power) and renderer:invalidation_snapshot() or nil
          local prepare_start = window:time()
          compositor:update_models(pane_entries)
          local prepare_elapsed = window:time() - prepare_start
          local rendered, reason = compositor:render(pane_entries, now, window.debug_dirty, window.debug_boundaries)
          if rendered and not simulated_device_loss and simulated_device_loss_frame > 0 and metrics.frame_number + 1 >= simulated_device_loss_frame then
            simulated_device_loss = true
            rendered, reason = false, "native GPU error: simulated device loss"
          end
          if not rendered and reason ~= "zero-sized drawable" and reason ~= "surface occluded" then handle_render_failure(reason) end
          local frame_completed = window:time()
          if rendered and kitty_graphics_report and kitty_first_visible_at == nil then
            for _, entry in ipairs(pane_entries) do
              local images = entry.renderer.diagnostics.kitty_images or {}
              if images.active and images.instances > 0 and images.textures > 0 then
                kitty_first_visible_at = frame_completed
                kitty_first_visible_frame = metrics.frame_number + 1
                break
              end
            end
          end
          if rendered and pacing then pacing:present(frame_start, frame_completed, invalidation.reasons) end
          if rendered and power then power:present(invalidation.reasons, renderer.extension_manager:snapshot()) end
          metrics:record(frame_completed - frame_start, prepare_elapsed, renderer)
          if window.debug_metrics then metrics:report(now) end
          if max_frames > 0 and metrics.frame_number >= max_frames then break end
        elseif power and compositor:needs_render(pane_entries, now) then
          power:defer(window.minimized and "minimized" or "synchronized-output")
        end
      end
      if child_status and pty.eof and workspace:tab_count() == 1 then
        window:request_close()
      end
    end
    if terminal and (transferred_away == nil or terminal ~= transferred_away.terminal) then terminal:finish() end
    if kitty_graphics_report then
      if kitty_first_visible_at then
        local transfer_to_present_ms = kitty_transfer_started_at and (kitty_first_visible_at - kitty_transfer_started_at) * 1000 or -1
        io.stdout:write(string.format("Kiwi kitty graphics: first-visible=frame:%d transfer-to-present=%.3fms\n", kitty_first_visible_frame, transfer_to_present_ms))
      else
        io.stderr:write("Kiwi kitty graphics: first-visible=unavailable\n")
      end
    end
    if soak then
      local snapshot = soak:snapshot()
      io.stdout:write(string.format(
        "Kiwi device soak: duration=%.3fs resize=%d minimize=%d restore=%d\n",
        snapshot.duration_seconds,
        snapshot.lifecycle.resize,
        snapshot.lifecycle.minimize,
        snapshot.lifecycle.restore
      ))
    end
    if pacing then
      local path = Pacing.write_report(root, pacing_report, pacing, renderer)
      io.stdout:write("Kiwi pacing report: ", path, "\n")
    end
    if power then
      local path = Power.write_report(root, power_report, power, window:time())
      io.stdout:write("Kiwi power report: ", path, "\n")
    end
    if renderer and not options.release_mode and os.getenv("KIWI_GPU_TIMESTAMPS_REPORT") == "1" then report_gpu_timing(renderer) end
    if renderer and not options.release_mode and os.getenv("KIWI_PASS_BUDGETS_REPORT") == "1" then report_pass_budgets(renderer) end
    if os.getenv("KIWI_FRAMEBUFFER_CAPTURE_REPORT") == "1" then report_framebuffer_capture(context) end
    if options.inspect then
      local column = options.inspect.column or state.cursor.column
      local row = options.inspect.row or state.cursor.row
      assert(column >= 0 and column < state.columns and row >= 0 and row < state.rows, "--inspect coordinates are outside the terminal grid")
      io.stdout:write(TextInspector.format(TextInspector.describe(state, font, column, row, renderer.layout)), "\n")
    end
  end, debug.traceback)

  if options.application then options.application:unregister_controller(options.controller_id) end
  local preserve_transferred_session = options.moved_session ~= nil and not options.transfer_confirmed
  if preserve_transferred_session and options.moved_session.renderer then
    options.moved_session.renderer:destroy()
    options.moved_session.renderer = nil
  end
  if workspace and destroy_session then
    for _, pane in pairs(workspace.panes) do
      if not (preserve_transferred_session and pane.session == options.moved_session) then destroy_session(pane.session) end
    end
    pty = nil
    terminal = nil
    renderer = nil
  end
  if preserve_transferred_session then
    pty = nil
    terminal = nil
    renderer = nil
  end
  if accessibility then
    accessibility:destroy()
    accessibility = nil
  end
  if pty then pty:shutdown() end
  if terminal then terminal:close() end
  if recorder then recorder:close() end
  if renderer then renderer:destroy() end
  if font then font:destroy() end
  if context then context:destroy() end
  window:destroy()
  if not ok then error(result) end
end

return Controller
