local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local path = assert(arg[1], "usage: luajit src/kiwi/replay.lua <recording.jsonl>")
local state = State.new(80, 24)
local stats = Replay.apply_file(state, path)
io.stdout:write(Snapshot.encode(state), "\n")
io.stderr:write(string.format("replayed bytes=%d actions=%d errors=%d\n", stats.bytes, stats.actions, stats.errors))
