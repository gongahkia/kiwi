local Color = require("kiwi.terminal.color")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local stream = io.read("*a")
assert(#stream > 0, "terminfo contract received no tput output")

local state = State.new(8, 1)
local parser = Parser.new(state)
parser:feed(stream)
parser:finish()

local function colour(cell, channel, red, green, blue)
  local actual = Color.unpack(cell[channel])
  assert(actual.red == red and actual.green == green and actual.blue == blue,
    string.format("terminfo %s expected rgb=%d,%d,%d got rgb=%d,%d,%d", channel, red, green, blue, actual.red, actual.green, actual.blue))
end

colour(state:get(0, 0), "fg", 255, 0, 0)
colour(state:get(1, 0), "bg", 0, 0, 255)
colour(state:get(2, 0), "fg", 17, 34, 51)
colour(state:get(3, 0), "bg", 68, 85, 102)
assert(state:get(4, 0).underline_style == 3, "terminfo Smulx must select curly underline")
colour(state:get(4, 0), "underline_color", 18, 171, 52)
assert(require("bit").band(state:get(5, 0).flags, State.flags.italic) ~= 0, "terminfo sitm must select italic")
assert(require("bit").band(state:get(6, 0).flags, State.flags.italic + State.flags.underline) == 0, "terminfo resets must clear italic and underline")
assert(parser.stats.errors == 0 and parser.stats.ignored == 0, "terminfo output must be a clean parser stream")
assert((state.stats.unknown.csi or 0) == 0, "terminfo output must use implemented CSI sequences")
