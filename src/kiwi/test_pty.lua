local ffi = require("ffi")
local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local Pty = require("kiwi.process.pty")
local State = require("kiwi.terminal.state")

local function pump(command, columns, rows, on_responses)
  local pty = Pty.spawn(command, columns, rows, { TERM = "kiwi" })
  local state = State.new(columns, rows)
  local parser = Parser.new(function(action)
    state:apply(action)
  end)
  local transcript = {}
  for _ = 1, 400 do
    local output = pty:read_available()
    if #output > 0 then
      transcript[#transcript + 1] = output
      parser:feed(output)
    end
    local responses = state:pop_responses()
    if #responses > 0 then
      pty:enqueue(on_responses and on_responses(responses) or table.concat(responses))
      pty:flush()
    end
    local status = pty:poll_exit()
    if status and pty.eof then
      parser:finish()
      pty:shutdown()
      return table.concat(transcript), state, status
    end
    ffi.C.usleep(5000)
  end
  pty:shutdown()
  error("PTY integration test timed out")
end

local total = 0
local function test(name, callback)
  total = total + 1
  local ok, message = xpcall(callback, debug.traceback)
  if not ok then
    io.stderr:write("FAIL ", name, "\n", message, "\n")
    os.exit(1)
  end
  io.stdout:write("PASS ", name, "\n")
end

test("pty_launches_shell_independent_command_and_parses_output", function()
  local transcript, state, status = pump({ "/bin/sh", "-c", "printf 'hello\\r\\n\\033[31mred\\033[0m\\rX'; exit 7" }, 16, 4)
  Assert.equal(transcript, "hello\r\r\n\27[31mred\27[0m\rX")
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 7)
  Assert.equal(state:get(0, 1).glyph, "X")
  Assert.equal(state:get(1, 1).glyph, "e")
  Assert.truthy(state:get(1, 1).fg ~= state.default_cell.fg)
end)

test("pty_applies_initial_winsize_and_reaps_child", function()
  local transcript, _, status = pump({ "/bin/sh", "-c", "stty size" }, 11, 7)
  Assert.truthy(transcript:find("7 11", 1, true) ~= nil)
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 0)
end)

test("pty_resize_notifies_the_child_process_group", function()
  local pty = Pty.spawn({ "/bin/sh", "-c", "stty size; IFS= read -r line; stty size" }, 10, 6, { TERM = "kiwi" })
  local transcript = ""
  local resized = false
  local status
  for _ = 1, 400 do
    transcript = transcript .. pty:read_available()
    if not resized and transcript:find("6 10", 1, true) then
      pty:resize(13, 5)
      pty:enqueue("\n")
      pty:flush()
      resized = true
    end
    status = pty:poll_exit()
    if status and pty.eof then
      break
    end
    ffi.C.usleep(5000)
  end
  pty:shutdown()
  Assert.truthy(resized)
  Assert.truthy(transcript:find("5 13", 1, true) ~= nil)
  Assert.equal(status.kind, "exit")
end)

test("terminal_generated_response_returns_through_pty", function()
  local transcript, _, status = pump({ "/bin/sh", "-c", "stty -echo; printf '\\033[6n'; IFS= read -r reply; stty echo; printf 'reply:%s' \"$reply\"" }, 8, 2, function(responses)
    return table.concat(responses) .. "\n"
  end)
  Assert.truthy(transcript:find("reply:\27[1;1R", 1, true) ~= nil)
  Assert.equal(status.kind, "exit")
end)

io.stdout:write(string.format("%d deterministic PTY integration tests passed.\n", total))
