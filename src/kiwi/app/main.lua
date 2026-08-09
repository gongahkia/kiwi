local Context = require("kiwi.gpu.context")
local Demo = require("kiwi.app.demo")
local TextInspector = require("kiwi.diagnostics.text_inspector")
local FontSystem = require("kiwi.font.system")
local Keyboard = require("kiwi.input.keyboard")
local Metrics = require("kiwi.diagnostics.metrics")
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
      error("unknown option: " .. value .. "; use --demo, --inspect[=ROW,COLUMN], or -- <command> [args...]")
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

local function run_live(options)
  local window = Window.new(1600, 960, "Kiwi M2 terminal")
  local context
  local renderer
  local font
  local pty
  local recorder
  local ok, result = xpcall(function()
    context = Context.new(window)
    font = new_font(window)
    local columns, rows = dimensions(window, font)
    assert(columns ~= nil, "window has no drawable size")
    local state = State.new(columns, rows, {
      scrollback_limit = number_from_env("KIWI_SCROLLBACK", 2000),
      ambiguous_width = number_from_env("KIWI_AMBIGUOUS_WIDTH", 1),
    })
    local root = os.getenv("KIWI_ROOT") or "."
    pty = Pty.spawn(options.command or Pty.default_command(), columns, rows, {
      TERM = "kiwi",
      TERMINFO = root .. "/.build/terminfo",
    })
    local parser = Parser.new(state)
    if options.record then
      recorder = Replay.Recorder.new(options.record)
      recorder:resize(columns, rows)
    end
    renderer = Renderer.new(context, font, state)
    local metrics = Metrics.new(context, font, state, { pty = pty, parser = parser })
    local last_title
    local max_frames = number_from_env("KIWI_MAX_FRAMES", 0)
    local pty_read_budget = number_from_env("KIWI_PTY_READ_BUDGET", 4 * 1024)
    local next_frame = window:time()

    window:set_input_handlers(function(codepoint)
      local text = Keyboard.text(codepoint)
      if text then
        if recorder then recorder:input(text) end
        pty:enqueue(text)
      end
    end, function(key, action, modifiers)
      local encoded = Keyboard.key(key, action, modifiers, state.modes, glfw)
      if not encoded then
        return
      end
      if encoded.local_action == "scroll_up" then
        state:scroll_history(math.max(1, state.rows - 1))
      elseif encoded.local_action == "scroll_down" then
        state:scroll_history(-math.max(1, state.rows - 1))
      elseif encoded.bytes then
        if recorder then recorder:input(encoded.bytes) end
        pty:enqueue(encoded.bytes)
      end
    end)

    io.stdout:write(string.format("Kiwi M2: Unicode=17.0 TERM=kiwi child=%s grid=%dx%d primary=%s\n", options.command and options.command[1] or Pty.default_command()[1], columns, rows, font.font_path))
    while not window:should_close() do
      local now = window:time()
      if now < next_frame then
        window:wait_events(math.min(next_frame - now, 0.050))
      end
      window:poll_events()
      now = window:time()

      local output = pty:read_available(pty_read_budget)
      if #output > 0 then
        if recorder then recorder:output(output) end
        parser:feed(output)
      end
      local responses = state:pop_responses()
      if #responses > 0 then
        pty:enqueue(table.concat(responses))
      end
      pty:flush()
      local child_status = pty:poll_exit()
      if state.title and state.title ~= last_title then
        window:set_title(state.title)
        last_title = state.title
      end

      if now >= next_frame then
        local scale_changed = math.abs(content_scale(window) - font.content_scale) > 0.001
        if scale_changed then
          renderer:destroy()
          renderer = nil
          font:destroy()
          font = new_font(window)
          metrics.font = font
        end
        local new_columns, new_rows = dimensions(window, font)
        if new_columns and (scale_changed or new_columns ~= state.columns or new_rows ~= state.rows) then
          context:configure_surface()
          if new_columns ~= state.columns or new_rows ~= state.rows then
            state:resize(new_columns, new_rows)
            pty:resize(new_columns, new_rows)
            if recorder then recorder:resize(new_columns, new_rows) end
          else
            state:mark_all_dirty()
          end
          if renderer then renderer:destroy() end
          renderer = Renderer.new(context, font, state)
        end
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
        next_frame = now + 1 / 30
        if max_frames > 0 and metrics.frame_number >= max_frames then
          break
        end
      end
      if child_status and pty.eof then
        window:request_close()
      end
    end
    parser:finish()
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
