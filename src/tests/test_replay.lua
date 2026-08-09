local Assert = require("tests.assert")
local Base64 = require("kiwi.terminal.base64")
local Parser = require("kiwi.terminal.parser")
local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local function with_temporary_recording(callback)
  local path = os.tmpname()
  local ok, result = xpcall(function()
    return callback(path)
  end, debug.traceback)
  os.remove(path)
  if not ok then
    error(result)
  end
  return result
end

return {
  base64_round_trips_terminal_bytes = function()
    local bytes = "\0\27[31m€\255"
    Assert.equal(Base64.decode(Base64.encode(bytes)), bytes)
  end,
  recording_replay_matches_direct_parser_state = function()
    with_temporary_recording(function(path)
      local recording = Replay.Recorder.new(path)
      recording:resize(7, 3)
      recording:output("\27[31mred\27[0m\rX\n")
      recording:output("€")
      recording:close()

      local replayed = State.new(1, 1)
      local stats = Replay.apply_file(replayed, path)
      local direct = State.new(7, 3)
      local parser = Parser.new(function(action)
        direct:apply(action)
      end)
      parser:feed("\27[31mred\27[0m\rX\n€")
      parser:finish()
      Assert.equal(Snapshot.encode(replayed), Snapshot.encode(direct))
      Assert.equal(stats.bytes, #"\27[31mred\27[0m\rX\n€")
    end)
  end,
  replay_rejects_unsupported_versions = function()
    with_temporary_recording(function(path)
      local file = assert(io.open(path, "wb"))
      file:write('{"data":"QQ==","event":"output","v":2}\n')
      file:close()
      local state = State.new(2, 1)
      local ok = pcall(Replay.apply_file, state, path)
      Assert.equal(ok, false)
    end)
  end,
}
