local Replay = require("kiwi.terminal.replay")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local chunk_invariant = arg[1] == "--chunk-invariant"
local path = assert(arg[chunk_invariant and 2 or 1], "usage: luajit src/kiwi/replay.lua [--chunk-invariant] <recording.jsonl>")
local state
local stats
local chunking = "captured"
if chunk_invariant then
  state, stats = Replay.verify_chunk_invariance(path)
  chunking = "whole+one-byte+8-random"
else
  state = State.new(80, 24)
  stats = Replay.apply_file(state, path)
end
io.stdout:write(Snapshot.encode(state), "\n")
io.stderr:write(string.format("replayed bytes=%d actions=%d errors=%d ignored=%d unknown=csi:%d,esc:%d,osc:%d,string:%d chunking=%s\n", stats.bytes, stats.actions, stats.errors, stats.ignored, state.stats.unknown.csi, state.stats.unknown.esc, state.stats.unknown.osc, state.stats.unknown.string, chunking))
