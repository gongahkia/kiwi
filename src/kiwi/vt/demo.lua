local VT = require("kiwi.vt")
local Headless = require("kiwi.vt.headless")

local function parse_integer(argument, value)
  local number = tonumber(value)
  assert(number and number % 1 == 0 and number > 0, argument .. " needs a positive integer")
  return number
end

local function parse_options()
  local options = { columns = 80, rows = 24 }
  local index = 1
  while index <= #arg do
    local value = arg[index]
    if value == "--columns" then
      index = index + 1
      options.columns = parse_integer("--columns", arg[index])
    elseif value == "--rows" then
      index = index + 1
      options.rows = parse_integer("--rows", arg[index])
    elseif value == "--help" then
      io.stdout:write("usage: kiwi-vt [--columns N] [--rows N] < terminal-bytes\n")
      os.exit(0)
    else
      error("unknown option: " .. value .. "; use --columns N, --rows N, or --help")
    end
    index = index + 1
  end
  return options
end

local options = parse_options()
local terminal = VT.new({ columns = options.columns, rows = options.rows })
local bytes = io.read("*a")
if #bytes > 0 then terminal:write(bytes) end
terminal:finish()
local projection = Headless.render_terminal(terminal, { consume_damage = true, trim_trailing = true })
io.stdout:write(projection.text, "\n")
