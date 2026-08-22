local FontSystem = require("kiwi.font.system")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local Pty = require("kiwi.process.pty")
local Replay = require("kiwi.terminal.replay")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")

local mode = os.getenv("KIWI_PROFILE_MODE") or "ascii"
local valid_modes = {
  ascii = true,
  ascii_full = true,
  combining = true,
  cjk = true,
  mixed = true,
  replay = true,
  live_ascii = true,
}
assert(valid_modes[mode], "KIWI_PROFILE_MODE must be ascii, ascii_full, combining, cjk, mixed, replay, or live_ascii")

local function iterations_for_mode()
  local value = tonumber(os.getenv("KIWI_PROFILE_ITERATIONS"))
  if value and value > 0 then return math.floor(value) end
  return mode == "replay" and 1000 or 100000
end

local function reset_write_state(state)
  state.cursor.column = 0
  state.cursor.row = 0
  state.cursor.pending_wrap = false
  state:clear_grapheme_context()
  state.damage:clear()
  state.text_damage:clear()
end

local function input_for(name, alternate)
  if name == "ascii" or name == "ascii_full" then return string.rep(alternate and "B" or "A", 79) end
  if name == "combining" then return string.rep((alternate and "a" or "e") .. Utf8.encode(0x0301), 24) end
  if name == "cjk" then return string.rep(Utf8.encode(alternate and 0x6587 or 0x4e2d), 30) end
  return string.rep((alternate and "B" or "A") .. Utf8.encode(0x0301) .. " " .. Utf8.encode(0x4e2d) .. " " .. Utf8.encode(0x1f469) .. Utf8.encode(0x200d) .. Utf8.encode(0x1f680), 8)
end

local function profile_parser_state()
  local iterations = iterations_for_mode()
  local state = State.new(80, 1)
  local parser = Parser.new(state)
  for iteration = 1, iterations do
    parser:feed(input_for(mode, iteration % 2 == 0))
    parser:finish()
    reset_write_state(state)
  end
end

local function profile_full_ascii()
  local iterations = iterations_for_mode()
  local system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
  local state = State.new(80, 1)
  local parser = Parser.new(state)
  local layout = Layout.new(system)
  for iteration = 1, iterations do
    parser:feed(input_for("ascii_full", iteration % 2 == 0))
    parser:finish()
    layout:update(state)
    reset_write_state(state)
  end
  system:destroy()
end

local function profile_replay()
  local iterations = iterations_for_mode()
  local path = os.getenv("KIWI_PROFILE_REPLAY") or "src/tests/fixtures/replay/live-color-cr.jsonl"
  local state = State.new(80, 24)
  for _ = 1, iterations do
    Replay.apply_file(state, path)
    state:reset()
    state.damage:clear()
    state.text_damage:clear()
  end
end

local function profile_live_ascii()
  local pty = Pty.spawn({ "/bin/sh", "-c", "head -c 8388608 /dev/zero | tr '\\000' A" }, 80, 24, { TERM = "xterm-kiwi", COLORTERM = "truecolor" })
  local state = State.new(80, 24, { scrollback_limit = 256 })
  local parser = Parser.new(state)
  local deadline = os.clock() + 90
  while true do
    local output = pty:read_available(4096)
    if #output > 0 then parser:feed(output) end
    local status = pty:poll_exit()
    if status and pty.eof then break end
    assert(os.clock() < deadline, "live ASCII profiling child timed out")
  end
  parser:finish()
  pty:shutdown()
end

if mode == "ascii_full" then
  profile_full_ascii()
elseif mode == "replay" then
  profile_replay()
elseif mode == "live_ascii" then
  profile_live_ascii()
else
  profile_parser_state()
end

io.stdout:write(string.format("profile-text mode=%s iterations=%d\n", mode, mode == "live_ascii" and 1 or iterations_for_mode()))
