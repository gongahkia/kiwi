local Context = require("kiwi.gpu.context")
local Demo = require("kiwi.app.demo")
local TextInspector = require("kiwi.diagnostics.text_inspector")
local FontSystem = require("kiwi.font.system")
local Clipboard = require("kiwi.input.clipboard")
local Hyperlink = require("kiwi.input.hyperlink")
local HyperlinkPointer = require("kiwi.input.hyperlink_pointer")
local Keyboard = require("kiwi.input.keyboard")
local Metrics = require("kiwi.diagnostics.metrics")
local Mouse = require("kiwi.input.mouse")
local SelectionPointer = require("kiwi.input.selection_pointer")
local Pty = require("kiwi.process.pty")
local Renderer = require("kiwi.renderer.renderer")
local Parser = require("kiwi.terminal.parser")
local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")
local Window = require("kiwi.platform.window")
local glfw = require("kiwi.ffi.glfw").constants

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value >= 0 and value or fallback
end

local function parse_options()
  local options = { demo = os.getenv("KIWI_DEMO") == "1" }
  local index = 1
  while index <= #arg do
    local value = arg[index]
    if value == "--demo" then
      options.demo = true
    elseif value == "--no-extensions" then
      options.no_extensions = true
    elseif value == "--record" then
      index = index + 1
      options.record = assert(arg[index], "--record needs a JSONL path")
    elseif value == "--replay" then
      index = index + 1
      options.replay = assert(arg[index], "--replay needs a JSONL path")
    elseif value == "--inspect" then
      options.inspect = {}
    elseif value:sub(1, 10) == "--inspect=" then
      local row, column = value:match("^%-%-inspect=(%d+),(%d+)$")
      if not row then error("--inspect expects zero-based ROW,COLUMN") end
      options.inspect = { row = tonumber(row), column = tonumber(column) }
    elseif value == "--" then
      options.command = {}
      for command_index = index + 1, #arg do
        options.command[#options.command + 1] = arg[command_index]
      end
      break
    else
      error("unknown option: " .. value .. "; use --demo, --no-extensions, --inspect[=ROW,COLUMN], or -- <command> [args...]")
    end
    index = index + 1
  end
  return options
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

local function new_font(window)
  local scale = content_scale(window)
  local font = FontSystem.new({
    pixel_height = math.max(1, math.floor(number_from_env("KIWI_FONT_PX", 20) * scale + 0.5)),
    font_path = os.getenv("KIWI_FONT"),
    primary_family = os.getenv("KIWI_FONT_FAMILY") or "monospace",
    ligatures = os.getenv("KIWI_LIGATURES") == "1",
    contextual_alternates = os.getenv("KIWI_CALT") == "1",
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

local function renderer_options(runtime_options)
  local options = {
    pass_metrics_enabled = os.getenv("KIWI_PASS_METRICS") == "1",
    pass_budgets_enabled = os.getenv("KIWI_PASS_BUDGETS") == "1",
    inspector_enabled = os.getenv("KIWI_RENDER_INSPECTOR") == "1",
    inspector_selected_pass = os.getenv("KIWI_RENDER_INSPECTOR_PASS"),
    selection_color = os.getenv("KIWI_SELECTION_COLOR"),
    search_color = os.getenv("KIWI_SEARCH_COLOR"),
    hyperlink_color = os.getenv("KIWI_HYPERLINK_COLOR"),
    extensions_enabled = not runtime_options.no_extensions,
    extensions = {},
  }
  if not runtime_options.no_extensions then
    options.extensions = extension_modules()
    options.extension_pass_limit = extension_limit_from_env("KIWI_EXTENSION_MAX_PASSES", 1, nil, true)
    options.extension_animation_hz = extension_limit_from_env("KIWI_EXTENSION_MAX_ANIMATION_HZ", 1 / 60, 60, false)
  end
  if os.getenv("KIWI_DEVELOPMENT") ~= "1" then return options end
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

local function run_live(options)
  local default_title = "Kiwi M2 terminal"
  local window = Window.new(1600, 960, default_title)
  local context
  local renderer
  local font
  local pty
  local recorder
  local ok, result = xpcall(function()
    context = Context.new(window, { gpu_timestamps = os.getenv("KIWI_GPU_TIMESTAMPS") == "1" })
    if os.getenv("KIWI_TIMESTAMP_PROBE") == "1" then
      local probe_ok, probe_message = context:probe_timestamp_queries()
      io.stderr:write("Kiwi timestamp probe: ", probe_ok and "supported: " or "unavailable: ", probe_message, "\n")
    end
    font = new_font(window)
    local columns, rows = dimensions(window, font)
    assert(columns ~= nil, "window has no drawable size")
    local state = State.new(columns, rows, {
      scrollback_limit = number_from_env("KIWI_SCROLLBACK", 2000),
      ambiguous_width = number_from_env("KIWI_AMBIGUOUS_WIDTH", 1),
    })
    local root = os.getenv("KIWI_ROOT") or "."
    local render_options = renderer_options(options)
    pty = Pty.spawn(options.command or Pty.default_command(), columns, rows, {
      TERM = "kiwi",
      TERMINFO = root .. "/.build/terminfo",
      COLORTERM = false,
    })
    local parser = Parser.new(state)
    if options.record then
      recorder = Replay.Recorder.new(options.record)
      recorder:resize(columns, rows)
    end
    renderer = Renderer.new(context, font, state, render_options)
    local clipboard = Clipboard.new(window)
    local hyperlink = Hyperlink.new(window)
    local metrics = Metrics.new(context, font, state, { clipboard = clipboard, pty = pty, parser = parser })
    local last_title
    local max_frames = number_from_env("KIWI_MAX_FRAMES", 0)
    local pty_read_budget = number_from_env("KIWI_PTY_READ_BUDGET", 4 * 1024)
    local mouse = Mouse.new()
    local mouse_generation = state.modes.mouse_generation
    local selection_pointer = SelectionPointer.new()
    local hyperlink_pointer = HyperlinkPointer.new(hyperlink, glfw)

    local function enqueue_input(bytes)
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

    local function update_search_title()
      local search = state:search_view()
      local title = search.editing and search.visible and "Kiwi search: " .. search.query or state.title or default_title
      if title ~= last_title then
        window:set_title(title)
        last_title = title
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

    window:set_input_handlers(function(codepoint)
      local text = Keyboard.text(codepoint)
      if text then
        local search = state:search_view()
        if search.editing and search.visible then
          local appended, status = state:search_append(text)
          if not appended then report_search_status(status) end
          renderer:invalidate("search")
        else
          enqueue_input(text)
        end
      end
    end, function(key, action, modifiers)
      if handle_search_key(key, action) then
        renderer:invalidate("search")
        return { handled = true, suppress_text = true }
      end
      local encoded = Keyboard.key(key, action, modifiers, state.modes, glfw)
      if not encoded then
        return nil
      end
      if encoded.local_action == "scroll_up" then
        state:scroll_history(math.max(1, state.rows - 1))
        renderer:invalidate("terminal")
      elseif encoded.local_action == "scroll_down" then
        state:scroll_history(-math.max(1, state.rows - 1))
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
        encoded = mouse:button(event, state.modes)
      elseif not hyperlink_handled and not selection_handled and event.kind == "motion" then
        encoded = mouse:motion(event, state.modes)
      elseif not hyperlink_handled and not selection_handled and event.kind == "wheel" then
        encoded = mouse:wheel(event, state.modes)
      end
      if encoded then enqueue_input(encoded) end
    end, function(focused)
      if not focused then selection_pointer:reset() end
      local encoded = mouse:focus(focused, state.modes)
      if encoded then enqueue_input(encoded) end
    end)

    io.stdout:write(string.format("Kiwi M2: Unicode=17.0 TERM=kiwi child=%s grid=%dx%d primary=%s\n", options.command and options.command[1] or Pty.default_command()[1], columns, rows, font.font_path))
    while not window:should_close() do
      local now = window:time()
      local deadline = renderer:next_render_deadline()
      if deadline and now < deadline then window:wait_events(math.min(deadline - now, 0.050)) else window:wait_events(0.050) end
      window:poll_events()
      now = window:time()

      local output = pty:read_available(pty_read_budget)
      if #output > 0 then
        if recorder then recorder:output(output) end
        parser:feed(output)
        if state.modes.mouse_generation ~= mouse_generation then
          mouse:reset()
          selection_pointer:reset()
          mouse_generation = state.modes.mouse_generation
        end
        renderer:invalidate("terminal")
      end
      local responses = state:pop_responses()
      if #responses > 0 then
        pty:enqueue(table.concat(responses))
      end
      pty:flush()
      local child_status = pty:poll_exit()
      update_search_title()

      do
        local scale_changed = math.abs(content_scale(window) - font.content_scale) > 0.001
        local previous_viewport = {
          columns = state.columns,
          rows = state.rows,
          drawable_width = context.width,
          drawable_height = context.height,
          content_scale = font.content_scale,
        }
        local previous_font
        if scale_changed then
          previous_font = font
          font = new_font(window)
          metrics.font = font
        end
        local new_columns, new_rows = dimensions(window, font)
        if new_columns and (scale_changed or new_columns ~= state.columns or new_rows ~= state.rows) then
          context:configure_surface()
          renderer:invalidate("resize")
          if new_columns ~= state.columns or new_rows ~= state.rows then
            state:resize(new_columns, new_rows)
            pty:resize(new_columns, new_rows)
            if recorder then recorder:resize(new_columns, new_rows) end
          else
            state:mark_all_dirty()
          end
          if renderer then
            renderer:resize(previous_viewport, {
              columns = state.columns,
              rows = state.rows,
              drawable_width = context.width,
              drawable_height = context.height,
              content_scale = font.content_scale,
            })
            renderer:destroy()
          end
          if previous_font then previous_font:destroy() end
          renderer = Renderer.new(context, font, state, render_options)
        end
        if window:take_shader_reload_request() then
          local reloaded, message = renderer:reload_shaders(true)
          report_shader_reload(reloaded, message)
          if reloaded then renderer:invalidate("configuration") end
        elseif renderer:shader_reload_enabled() then
          report_shader_reload(renderer:poll_shader_reload(now))
        end
        if renderer:needs_render(now) and renderer:can_present(state) then
        local frame_start = now
        local prepare_start = window:time()
        renderer:update_model(state)
        local prepare_elapsed = window:time() - prepare_start
        local rendered, reason = renderer:render(state, now, window.debug_dirty, window.debug_boundaries)
        if not rendered and reason ~= "zero-sized drawable" then
          if reason:sub(1, 17) == "native GPU error:" then
            error(reason)
          end
          context.window.resized = true
        end
        metrics:record(window:time() - frame_start, prepare_elapsed, renderer)
        if window.debug_metrics then
          metrics:report(now)
        end
        if max_frames > 0 and metrics.frame_number >= max_frames then
          break
        end
        end
      end
      if child_status and pty.eof then
        window:request_close()
      end
    end
    parser:finish()
    if renderer and os.getenv("KIWI_GPU_TIMESTAMPS_REPORT") == "1" then report_gpu_timing(renderer) end
    if renderer and os.getenv("KIWI_PASS_BUDGETS_REPORT") == "1" then report_pass_budgets(renderer) end
    if options.inspect then
      local column = options.inspect.column or state.cursor.column
      local row = options.inspect.row or state.cursor.row
      assert(column >= 0 and column < state.columns and row >= 0 and row < state.rows, "--inspect coordinates are outside the terminal grid")
      io.stdout:write(TextInspector.format(TextInspector.describe(state, font, column, row, renderer.layout)), "\n")
    end
  end, debug.traceback)

  if pty then pty:shutdown() end
  if recorder then recorder:close() end
  if renderer then renderer:destroy() end
  if font then font:destroy() end
  if context then context:destroy() end
  window:destroy()
  if not ok then error(result) end
end

local function run_replay(path)
  local state = State.new(80, 24)
  local stats = Replay.apply_file(state, path)
  io.stdout:write(Snapshot.encode(state), "\n")
  io.stderr:write(string.format("Kiwi replay: bytes=%d actions=%d errors=%d\n", stats.bytes, stats.actions, stats.errors))
end

local options = parse_options()
if options.replay then
  run_replay(options.replay)
elseif options.demo then
  Demo.run()
else
  run_live(options)
end
