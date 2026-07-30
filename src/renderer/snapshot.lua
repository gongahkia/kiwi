local Errors = require("runtime.errors")

local Snapshot = {}

Snapshot.contract = {
  from_terminal = "from_terminal(terminal) -> renderer_snapshot | nil, error",
}

local function invariant_error(message, detail)
  return nil, Errors.new("internal_invariant_error", message, detail)
end

function Snapshot.from_terminal(terminal)
  if type(terminal) ~= "table" or type(terminal.config) ~= "table" then
    return invariant_error("renderer terminal source is invalid")
  end
  if type(terminal.config.columns) ~= "number" or type(terminal.config.rows) ~= "number" then
    return invariant_error("renderer terminal dimensions are invalid")
  end
  local screen
  if terminal.active_buffer == "primary" then
    screen = terminal.primary_screen
  elseif terminal.active_buffer == "alternate" then
    screen = terminal.alternate_screen
  else
    return invariant_error("renderer terminal active buffer is invalid")
  end
  if type(screen) ~= "table" or type(screen.rows) ~= "table" then
    return invariant_error("renderer terminal screen is invalid")
  end
  if type(terminal.cursor) ~= "table" or type(terminal.modes) ~= "table" then
    return invariant_error("renderer terminal cursor or modes are invalid")
  end
  return {
    columns = terminal.config.columns,
    cursor = terminal.cursor,
    cursor_visible = terminal.modes.cursor_visible,
    rows = terminal.config.rows,
    screen = screen,
  }
end

return Snapshot
