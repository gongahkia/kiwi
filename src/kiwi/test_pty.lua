local ffi = require("ffi")
local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local Pty = require("kiwi.process.pty")
local State = require("kiwi.terminal.state")

local function pump(command, columns, rows, on_responses, environment)
  local pty = Pty.spawn(command, columns, rows, environment or { TERM = "xterm-kiwi", COLORTERM = "truecolor" })
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

test("pty_applies_the_advertised_child_terminal_environment", function()
  local transcript, _, status = pump({ "/bin/sh", "-c", "printf 'term=%s colorterm=%s' \"$TERM\" \"${COLORTERM-unset}\"" }, 16, 4, nil, {
    TERM = "xterm-kiwi",
    COLORTERM = "truecolor",
  })
  Assert.equal(transcript, "term=xterm-kiwi colorterm=truecolor")
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 0)
end)

test("pty_resolves_unqualified_commands_with_the_inherited_path", function()
  local transcript, _, status = pump({ "sh", "-c", "printf path-search" }, 16, 4)
  Assert.equal(transcript, "path-search")
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 0)
end)

test("pty_read_budget_preserves_all_output_across_multiple_polls", function()
  local pty = Pty.spawn({ "/bin/sh", "-c", "printf 'abcdefghijklmnopqrstuvwxyz'" }, 16, 4, { TERM = "xterm-kiwi" })
  local transcript = ""
  local status
  for _ = 1, 400 do
    local output = pty:read_available(4)
    Assert.truthy(#output <= 4)
    transcript = transcript .. output
    status = pty:poll_exit()
    if status and pty.eof then
      break
    end
    ffi.C.usleep(5000)
  end
  pty:shutdown()
  Assert.equal(transcript, "abcdefghijklmnopqrstuvwxyz")
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 0)
end)

test("pty_applies_initial_winsize_and_reaps_child", function()
  local transcript, _, status = pump({ "/bin/sh", "-c", "stty size" }, 11, 7)
  Assert.truthy(transcript:find("7 11", 1, true) ~= nil)
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 0)
end)

test("pty_resize_notifies_the_child_process_group", function()
  local pty = Pty.spawn({ "/bin/sh", "-c", "stty size; IFS= read -r line; stty size" }, 10, 6, { TERM = "xterm-kiwi" })
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

test("pty_interactive_shell_accepts_input_and_exits", function()
  local pty = Pty.spawn({ "/bin/sh" }, 20, 4, { TERM = "xterm-kiwi" })
  pty:enqueue("printf 'typed-from-pty\\n'\nexit\n")
  pty:flush()
  local transcript = ""
  local status
  for _ = 1, 400 do
    transcript = transcript .. pty:read_available()
    status = pty:poll_exit()
    if status and pty.eof then
      break
    end
    ffi.C.usleep(5000)
  end
  pty:shutdown()
  Assert.truthy(transcript:find("typed-from-pty", 1, true) ~= nil)
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 0)
end)

test("pty_discards_a_terminal_response_after_the_child_closes_its_slave", function()
  local pty = Pty.spawn({ "/bin/sh", "-c", "stty -echo; printf '\\033[6n'; exit 0" }, 8, 2, { TERM = "xterm-kiwi" })
  local transcript = ""
  for _ = 1, 400 do
    transcript = transcript .. pty:read_available()
    if transcript:find("\27[6n", 1, true) ~= nil then break end
    ffi.C.usleep(5000)
  end
  Assert.truthy(transcript:find("\27[6n", 1, true) ~= nil)
  ffi.C.usleep(20000)
  pty:enqueue("\27[1;1R")
  Assert.equal(pty:flush(), false)
  Assert.truthy(pty.eof)
  pty:shutdown()
end)

test("pty_ctrl_c_reaches_the_foreground_process_group", function()
  local pty = Pty.spawn({ "/bin/sh", "-c", "trap 'printf caught-int; exit 0' INT; while :; do sleep 1; done" }, 20, 4, { TERM = "xterm-kiwi" })
  ffi.C.usleep(20000)
  pty:enqueue("\3")
  pty:flush()
  local transcript = ""
  local status
  for _ = 1, 400 do
    transcript = transcript .. pty:read_available()
    status = pty:poll_exit()
    if status and pty.eof then
      break
    end
    ffi.C.usleep(5000)
  end
  pty:shutdown()
  Assert.truthy(transcript:find("caught-int", 1, true) ~= nil)
  Assert.equal(status.kind, "exit")
  Assert.equal(status.code, 0)
end)

test("pty_shutdown_reaps_a_hup_and_term_resistant_child", function()
  local pty = Pty.spawn({ "/bin/sh", "-c", "trap '' HUP TERM; while :; do sleep 1; done" }, 20, 4, { TERM = "xterm-kiwi" })
  ffi.C.usleep(20000)
  pty:shutdown()
  Assert.truthy(pty.exited)
  Assert.equal(pty.exit_status.kind, "signal")
  Assert.equal(pty.exit_status.signal, 9)
  Assert.equal(pty.fd, nil)
end)

test("pty_sessions_keep_input_output_and_lifecycle_isolated", function()
  local first = Pty.spawn({ "/bin/sh", "-c", "IFS= read -r value; printf 'first:%s' \"$value\"" }, 10, 4, { TERM = "xterm-kiwi" })
  local second = Pty.spawn({ "/bin/sh", "-c", "IFS= read -r value; printf 'second:%s' \"$value\"" }, 17, 5, { TERM = "xterm-kiwi" })
  first:enqueue("alpha\n")
  second:enqueue("beta\n")
  first:flush()
  second:flush()
  local first_output, second_output = "", ""
  local first_status, second_status
  for _ = 1, 400 do
    first_output = first_output .. first:read_available()
    second_output = second_output .. second:read_available()
    first_status = first:poll_exit()
    second_status = second:poll_exit()
    if first_status and first.eof and second_status and second.eof then break end
    ffi.C.usleep(5000)
  end
  first:shutdown()
  second:shutdown()
  Assert.truthy(first_output:find("first:alpha", 1, true) ~= nil)
  Assert.truthy(second_output:find("second:beta", 1, true) ~= nil)
  Assert.truthy(first_output:find("second:beta", 1, true) == nil)
  Assert.truthy(second_output:find("first:alpha", 1, true) == nil)
  Assert.equal(first_status.kind, "exit")
  Assert.equal(second_status.kind, "exit")
end)

io.stdout:write(string.format("%d deterministic PTY integration tests passed.\n", total))
