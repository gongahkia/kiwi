-- One independently owned terminal session rendered into one GtkGLArea page.
-- The native tab group owns widget composition; this module owns only Kiwi
-- terminal, PTY, input, renderer, and accessibility state for that page.
local AtspiProjection = require("kiwi.accessibility.atspi")
local Clipboard = require("kiwi.input.clipboard")
local Composition = require("kiwi.input.composition")
local FontSystem = require("kiwi.font.system")
local HostEffects = require("kiwi.app.host_effects")
local Hyperlink = require("kiwi.input.hyperlink")
local HyperlinkPointer = require("kiwi.input.hyperlink_pointer")
local Keyboard = require("kiwi.input.keyboard")
local Mouse = require("kiwi.input.mouse")
local ScrollbarPointer = require("kiwi.input.scrollbar_pointer")
local ScrollbackWheel = require("kiwi.input.scrollback_wheel")
local Pty = require("kiwi.process.pty")
local GtkGLConsumer = require("kiwi.renderer.gtk_gl_consumer")
local SelectionPointer = require("kiwi.input.selection_pointer")
local ShellIntegration = require("kiwi.process.shell_integration")
local TextLab = require("kiwi.text.lab")
local Utf8 = require("kiwi.terminal.utf8")
local VT = require("kiwi.vt")
local VTInternal = require("kiwi.vt.internal")

local Session = {}
Session.__index = Session

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
  return math.max(1, math.floor(math.max(1, width) / font.cell_width)),
    math.max(1, math.floor(math.max(1, height) / font.cell_height))
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

local function consumer_options(configuration, next_revision)
  return {
    command_region_color = configuration.command_region_color,
    command_region_visual_enabled = configuration.command_regions,
    hyperlink_color = configuration.hyperlink_color,
    next_revision = next_revision,
    search_color = configuration.search_color,
    selection_color = configuration.selection_color,
    scrollbar_policy = configuration.scrollbar,
    text_backend = TextLab.requested_backend(),
  }
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

function Session.new(window, host, configuration, options)
  assert(type(window) == "table" and type(host) == "table", "GTK GL session needs a page and host")
  assert(type(configuration) == "table" and type(options) == "table", "GTK GL session needs configuration and options")
  local self = setmetatable({
    configuration = configuration,
    default_title = options.default_title or "Kiwi GTK GL terminal",
    host = host,
    is_selected = options.is_selected,
    on_product_key = options.on_product_key,
    window = window,
  }, Session)
  self.glfw = host.keymap
  self.font = new_font(window, configuration)
  self.columns, self.rows = dimensions(window, self.font)
  self.terminal = VT.new({
    columns = self.columns,
    rows = self.rows,
    state_options = {
      scrollback_limit = configuration.scrollback_limit,
      ambiguous_width = configuration.ambiguous_width,
      osc52_read = configuration.osc52_read == "allow",
      osc52_write = configuration.osc52_write,
      keyboard_supported_flags = host.keyboard_supported_flags_for and
        host.keyboard_supported_flags_for(window) or host.keyboard_supported_flags,
      cell_width = self.font.cell_width,
      cell_height = self.font.cell_height,
      colors = { foreground = configuration.foreground, background = configuration.background,
        palette = configuration.palette },
    },
  })
  self.state = VTInternal.state(self.terminal)
  local root = os.getenv("KIWI_ROOT") or "."
  local environment = {
    TERM = "xterm-kiwi",
    TERMINFO = os.getenv("KIWI_TERMINFO") or root .. "/.build/terminfo",
    COLORTERM = "truecolor",
  }
  local command = options.command
  if command == nil and configuration.shell_integration == "auto" then
    local integration_environment
    command, integration_environment = ShellIntegration.prepare(Pty.default_command(),
      os.getenv("KIWI_INTEGRATION_DIR") or root .. "/integrations/v1")
    for name, value in pairs(integration_environment) do environment[name] = value end
  else
    command = command or Pty.default_command()
    if configuration.shell_integration == "none" then environment.KIWI_SHELL_INTEGRATION = false end
  end
  self.pty = Pty.spawn(command, self.columns, self.rows, environment, { cwd = options.initial_cwd })
  self.clipboard = Clipboard.new(window)
  self.host_effects = HostEffects.new(configuration, host, window)
  self.hyperlink = Hyperlink.new(window)
  self.hyperlink_pointer = HyperlinkPointer.new(self.hyperlink, self.glfw)
  self.mouse = Mouse.new()
  self.scrollback_wheel = ScrollbackWheel.new()
  self.scrollbar_pointer = ScrollbarPointer.new()
  self.selection_pointer = SelectionPointer.new()
  self.composition = Composition.new()
  self.composition:enter()
  self.last_title = self.default_title
  self.window_focused = true
  self.max_frames = number_from_env("KIWI_MAX_FRAMES", 0)
  self.read_budget = number_from_env("KIWI_PTY_READ_BUDGET", 4 * 1024)
  self.render_timeout = positive_number_from_env("KIWI_GTK_GL_RENDER_TIMEOUT", 3)
  self.consumer = GtkGLConsumer.new(window, self.font, self.state, consumer_options(configuration))
  self.accessibility = host.accessibility_new and host.accessibility_new(window) or nil
  self.accessibility_projection = AtspiProjection.new()
  self:_install_input_handlers()
  return self
end

function Session:_enqueue_input(bytes)
  if self.pty and bytes and #bytes > 0 then self.pty:enqueue(bytes) end
end

function Session:_invalidate(reason)
  if self.consumer then self.consumer:invalidate(reason or "terminal") end
end

function Session:_update_preedit_overlay(update)
  local preedit = update.preedit
  if preedit.text == "" then
    self.state.ime_preedit = nil
  else
    self.state.ime_preedit = { column = self.state.cursor.column,
      cursor_begin = preedit.cursor_begin, cursor_end = preedit.cursor_end,
      row = self.state.cursor.row, text = preedit.text }
  end
  self:_invalidate("terminal")
end

function Session:_apply_preedit(text, selection_start, selection_end)
  if not self.composition.focused then self.composition:enter() end
  local accepted, status = self.composition:offer_preedit(text, selection_start, selection_end)
  if not accepted then
    io.stderr:write("Kiwi IME preedit rejected: ", status, "\n")
    return
  end
  self:_update_preedit_overlay(assert(self.composition:done()))
end

function Session:_apply_commit(text)
  if not self.composition.focused then self.composition:enter() end
  local accepted = self.composition:offer_preedit("", 0, 0)
  if accepted then self:_update_preedit_overlay(assert(self.composition:done())) end
  local status
  accepted, status = self.composition:offer_commit(text)
  if not accepted then
    io.stderr:write("Kiwi IME commit rejected: ", status, "\n")
    return nil
  end
  local update = assert(self.composition:done())
  self:_update_preedit_overlay(update)
  return update.commit
end

function Session:_handle_committed_text(text)
  if text == nil or #text == 0 then return end
  local search = self.state:search_view()
  if search.editing and search.visible then
    local appended, status = self.state:search_append(text)
    if not appended then io.stderr:write("Kiwi search: ", status:gsub("-", " "), "\n") end
    self:_invalidate("search")
  else
    self:_enqueue_input(text)
  end
end

function Session:_handle_search_key(key, action)
  local search = self.state:search_view()
  if not search.editing or not search.visible then return false end
  if key == self.glfw.key_escape then
    if action == self.glfw.press then self.state:clear_search() end
    return true
  end
  if key == self.glfw.key_backspace then
    if action == self.glfw.press or action == self.glfw.repeat_action then self.state:search_backspace() end
    return true
  end
  if key == self.glfw.key_enter then
    if action == self.glfw.press then
      local _, status = self.state:search_submit("forward")
      if status ~= "matches" then io.stderr:write("Kiwi search: ", status:gsub("-", " "), "\n") end
    end
    return true
  end
  return false
end

function Session:_handle_local_action(encoded)
  if encoded.local_action == "scroll_up" then
    self.state:scroll_history(math.max(1, self.state.rows - 1)); self:_invalidate("terminal")
  elseif encoded.local_action == "scroll_down" then
    self.state:scroll_history(-math.max(1, self.state.rows - 1)); self:_invalidate("terminal")
  elseif encoded.local_action and encoded.local_action:match("^region_") then
    local direction, role = encoded.local_action:match("^region_([^_]+)_([^_]+)$")
    local _, status = self.state:navigate_command_region(role, direction == "next" and "forward" or "backward")
    report_region_status(status); self:_invalidate("terminal")
  elseif encoded.local_action == "copy" then
    local copied, status = self.clipboard:copy(self.state)
    if not copied then report_clipboard_failure("copy", status) end
  elseif encoded.local_action == "paste" then
    local bytes, status = self.clipboard:paste(self.state)
    if bytes then self:_enqueue_input(bytes) elseif status ~= "empty" then report_clipboard_failure("paste", status) end
  elseif encoded.local_action == "search_begin" then
    self.state:search_begin("forward"); self:_invalidate("search")
  elseif encoded.local_action == "search_next" or encoded.local_action == "search_previous" then
    local direction = encoded.local_action == "search_next" and "forward" or "backward"
    local search = self.state:search_view()
    local _, status = search.editing and search.visible and self.state:search_submit(direction) or self.state:search_navigate(direction)
    if status ~= "matches" then io.stderr:write("Kiwi search: ", status:gsub("-", " "), "\n") end
    self:_invalidate("search")
  elseif encoded.local_action == "open_hyperlink" then
    local opened, status = self.hyperlink:activate(self.state:hyperlink_at_cursor())
    if not opened then report_hyperlink_failure(status) end
  elseif encoded.bytes then
    self:_enqueue_input(encoded.bytes)
  end
end

function Session:_install_input_handlers()
  self.window:set_input_handlers(function(codepoints, key_event)
    if self.closed then return end
    if key_event then
      self:_apply_commit("")
      local encoded = Keyboard.key(key_event.key, key_event.action, key_event.modifiers,
        self.state.modes, self.glfw, { associated_text = codepoints,
          unicode_key = key_event.variants and key_event.variants.unicode_key,
          layout_key = key_event.variants and key_event.variants.layout_key,
          shifted_key = key_event.variants and key_event.variants.shifted_key,
          base_key = key_event.variants and key_event.variants.base_key })
      if encoded then self:_handle_local_action(encoded) end
      return
    end
    self:_handle_committed_text(Keyboard.text_sequence(codepoints, self.state.modes))
  end, function(key, action, modifiers, variants)
    if self.closed then return { handled = true, suppress_text = true } end
    if self.on_product_key and self.on_product_key(self, key, action, modifiers) then
      return { handled = true, suppress_text = true }
    end
    if self:_handle_search_key(key, action) then
      self:_invalidate("search")
      return { handled = true, suppress_text = true }
    end
    if Keyboard.should_defer_text(key, action, modifiers, self.state.modes, self.glfw, variants) then
      return { handled = true, defer_text = true }
    end
    local encoded = Keyboard.key(key, action, modifiers, self.state.modes, self.glfw, variants)
    if not encoded then return nil end
    self:_handle_local_action(encoded)
    return { handled = true, suppress_text = encoded.suppress_text }
  end, function(event)
    if self.closed then return end
    event.time = self.window:time()
    local scale = self.font.content_scale or 1
    event.selection_column, event.selection_row = SelectionPointer.cell_position(event.x, event.y, scale,
      self.font.cell_width, self.font.cell_height, self.state.columns, self.state.rows)
    event.column, event.row = event.selection_column + 1, event.selection_row + 1
    event.pixel_width = math.max(1, math.floor(self.state.columns * self.font.cell_width))
    event.pixel_height = math.max(1, math.floor(self.state.rows * self.font.cell_height))
    event.pixel_x = math.max(1, math.min(event.pixel_width, math.floor(event.x * scale) + 1))
    event.pixel_y = math.max(1, math.min(event.pixel_height, math.floor(event.y * scale) + 1))
    local scrollbar_handled, scrollbar_changed = self.scrollbar_pointer:handle(event, self.state,
      ScrollbarPointer.descriptor(self.state, self.configuration.scrollbar))
    if scrollbar_changed then self:_invalidate("scrollbar") end
    local hyperlink_handled, hyperlink_opened, hyperlink_status = false, false, nil
    if not scrollbar_handled then hyperlink_handled, hyperlink_opened, hyperlink_status = self.hyperlink_pointer:handle(event, self.state, self.state.modes) end
    if hyperlink_handled and not hyperlink_opened then report_hyperlink_failure(hyperlink_status) end
    local selection_handled, selection_changed = false, false
    if not scrollbar_handled and not hyperlink_handled then selection_handled, selection_changed = self.selection_pointer:handle(event, self.state, self.state.modes, self.configuration.mouse_shift_capture) end
    if selection_changed then self:_invalidate("selection") end
    if not scrollbar_handled and not hyperlink_handled and not selection_handled then
      local encoded
      if event.kind == "button" then encoded = self.mouse:button(event, self.state:input_modes())
      elseif event.kind == "motion" then encoded = self.mouse:motion(event, self.state:input_modes())
      elseif event.kind == "wheel" then
        local history_lines = self.scrollback_wheel:consume(event, self.state:input_modes())
        if history_lines ~= nil then
          self.state:scroll_history(history_lines)
          self:_invalidate("terminal")
        else
          encoded = self.mouse:wheel(event, self.state:input_modes())
        end
      end
      if encoded then self:_enqueue_input(encoded) end
    end
  end, function(focused)
    if self.closed then return end
    self.window_focused = focused
    if focused then
      self.composition:enter()
    else
      self.selection_pointer:reset(); self.scrollbar_pointer:reset(); self.state.ime_preedit = nil
      self.composition:leave(); self:_invalidate("terminal")
    end
    local encoded = self.mouse:focus(focused, self.state:input_modes())
    if encoded then self:_enqueue_input(encoded) end
  end)
  local enabled, reason = self.host.enable_text_input(self.window,
    function(...)
      if not self.closed then return self:_apply_preedit(...) end
    end,
    function(text)
      if self.closed then return end
      local committed = self:_apply_commit(text)
      local codepoints = codepoints_from_utf8(committed)
      self:_handle_committed_text(codepoints and Keyboard.text_sequence(codepoints, self.state.modes) or nil)
    end)
  if not enabled then io.stderr:write("Kiwi IME: unavailable: ", reason, "\n") end
end

function Session:_sync_accessibility()
  if self.accessibility == nil then return end
  local projection = self.accessibility_projection:project(self.state)
  local updated, reason = self.accessibility:update(projection, self.last_title, self.window_focused)
  if updated then
    self.accessibility:poll()
  else
    self.accessibility:destroy(); self.accessibility = nil
    if os.getenv("KIWI_ACCESSIBILITY_DIAGNOSTICS") == "1" then
      io.stderr:write("Kiwi accessibility: disabled after provider failure: ", reason, "\n")
    end
  end
end

function Session:_sync_text_input_caret()
  if type(self.host.set_text_input_caret) ~= "function" then return end
  local scale = self.font.content_scale or 1
  self.host.set_text_input_caret(self.window, self.state.cursor.column * self.font.cell_width / scale,
    self.state.cursor.row * self.font.cell_height / scale, math.max(1, self.font.cell_width / scale),
    math.max(1, self.font.cell_height / scale))
end

function Session:_recreate_consumer()
  local revision = self.consumer.revision
  self.consumer:destroy()
  self.consumer = GtkGLConsumer.new(self.window, self.font, self.state, consumer_options(self.configuration, revision))
end

function Session:_resize_if_needed()
  local scale_changed = math.abs(content_scale(self.window) - self.font.content_scale) > 0.001
  local columns, rows = dimensions(self.window, self.font)
  if scale_changed then
    local previous_font = self.font
    local revision = self.consumer.revision
    self.consumer:destroy()
    self.font = new_font(self.window, self.configuration)
    self.terminal:set_cell_metrics(self.font.cell_width, self.font.cell_height)
    columns, rows = dimensions(self.window, self.font)
    previous_font:destroy()
    self.consumer = GtkGLConsumer.new(self.window, self.font, self.state, consumer_options(self.configuration, revision))
    self.window.resized = true
  end
  if self.window.resized or columns ~= self.columns or rows ~= self.rows then
    self.columns, self.rows = columns, rows
    self.terminal:resize(columns, rows)
    self.pty:resize(columns, rows)
    self.window.resized = false
    self:_recreate_consumer()
  end
end

function Session:_drain_terminal(now, focused)
  local output = self.pty:read_available(self.read_budget)
  if #output > 0 then self.terminal:write(output); self:_invalidate("terminal") end
  local responses = self.terminal:pop_responses()
  if #responses > 0 then self.pty:enqueue(table.concat(responses)) end
  for _, effect in ipairs(self.terminal:pop_effects()) do
    if effect.kind == "clipboard_write_requested" then
      local written, status = self.clipboard:write_osc52(effect.value.text)
      if not written then io.stderr:write("Kiwi OSC 52 clipboard write rejected: ", status, "\n") end
    elseif effect.kind == "clipboard_read_requested" then
      local reply, status = self.clipboard:read_osc52_reply(effect.value.selection, effect.value.maximum_bytes)
      if reply then self.pty:enqueue(reply) else io.stderr:write("Kiwi OSC 52 clipboard read rejected: ", status, "\n") end
    elseif effect.kind == "pointer_shape_changed" and self.host.set_pointer_shape then
      self.host.set_pointer_shape(self.window, effect.value.shape)
    else
      local consumed, status, first_report = self.host_effects:consume(effect, {
        focused = focused,
        now = now,
        source = self,
      })
      if consumed and first_report and (status == "invalid" or status == "unavailable" or status == "rejected") then
        local subject = effect.kind == "shell_marker" and "command-finish notification"
          or effect.kind == "notification_requested" and "OSC 9 notification" or "OSC 9 progress"
        io.stderr:write("Kiwi ", subject, " ignored: ", status, "\n")
      end
    end
  end
  self.pty:flush()
  return self.pty:poll_exit()
end

function Session:next_deadline()
  if self.closed then return nil end
  return self.consumer:next_render_deadline()
end

function Session:tick(now)
  if self.closed then return "complete" end
  local selected = self.is_selected == nil or self.is_selected(self.window)
  if self.render_target_revision ~= nil then
    if not selected then return end
    local state, reason = self.window:gl_area_state()
    if state and state.rendered_revision >= self.render_target_revision then return "complete" end
    if now >= self.render_target_deadline then
      error("Kiwi GTK GL presentation did not render revision " .. tostring(self.render_target_revision) .. ": " .. tostring(reason or "render callback timed out"))
    end
    return
  end
  self:_resize_if_needed()
  local child_status = self:_drain_terminal(now, self.window_focused and selected)
  local search = self.state:search_view()
  local title = search.editing and search.visible and "Kiwi search: " .. search.query or self.state.title or self.default_title
  if title ~= self.last_title then self.window:set_title(title); self.last_title = title end
  self:_sync_accessibility(); self:_sync_text_input_caret()
  if selected and not self.window.minimized and self.consumer:needs_render(now) then
    local rendered, reason = self.consumer:render(self.state, now, self.window.debug_dirty, self.window.debug_boundaries)
    if rendered then
      self.frames = (self.frames or 0) + 1
      if self.max_frames > 0 and self.frames >= self.max_frames then
        self.render_target_revision = self.consumer.revision - 1
        self.render_target_deadline = self.window:time() + self.render_timeout
      end
    elseif reason ~= "synchronized-output" then
      error("Kiwi GTK GL presentation rejected a frame: " .. tostring(reason))
    end
  end
  if child_status and self.pty.eof and self.render_target_revision == nil then
    self.render_target_revision = self.consumer.revision - 1
    self.render_target_deadline = self.window:time() + self.render_timeout
  end
end

function Session:shutdown()
  if self.closed then return end
  self.closed = true
  if self.accessibility then self.accessibility:destroy(); self.accessibility = nil end
  if self.consumer then self.consumer:destroy(); self.consumer = nil end
  if self.pty then self.pty:shutdown(); self.pty = nil end
  if self.terminal then self.terminal:finish(); self.terminal:close(); self.terminal = nil end
  if self.font then self.font:destroy(); self.font = nil end
end

return Session
