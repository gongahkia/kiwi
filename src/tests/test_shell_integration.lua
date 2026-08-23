local Assert = require("tests.assert")
local Actions = require("kiwi.terminal.actions")
local Parser = require("kiwi.terminal.parser")
local Replay = require("kiwi.terminal.replay")
local ShellIntegration = require("kiwi.terminal.shell_integration")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local function with_recording(callback)
  local path = os.tmpname()
  local ok, result = xpcall(function() return callback(path) end, debug.traceback)
  os.remove(path)
  if not ok then error(result) end
  return result
end

return {
  shell_metadata_derives_only_safe_local_paths_for_new_sessions = function()
    local localhost = assert(ShellIntegration.parse_cwd("file://localhost/private/tmp/kiwi%20work"))
    Assert.equal(ShellIntegration.local_path(localhost, "other-host"), "/private/tmp/kiwi work")
    local local_host = assert(ShellIntegration.parse_cwd("file://workstation/private/tmp/kiwi"))
    Assert.equal(ShellIntegration.local_path(local_host, "workstation.local"), "/private/tmp/kiwi")
    local remote = assert(ShellIntegration.parse_cwd("file://remote.example/private/tmp/kiwi"))
    Assert.equal(ShellIntegration.local_path(remote, "workstation.local"), nil)
    local malformed = assert(ShellIntegration.parse_cwd("file:///private/tmp/kiwi%2"))
    Assert.equal(ShellIntegration.local_path(malformed, "workstation"), nil)
    local nul = assert(ShellIntegration.parse_cwd("file:///private/tmp/kiwi%00"))
    Assert.equal(ShellIntegration.local_path(nul, "workstation"), nil)
  end,

  shell_metadata_emits_a_bounded_cwd_effect = function()
    local effects = {}
    local state = State.new(4, 1, {
      effect_sink = function(kind, value)
        effects[#effects + 1] = { kind = kind, value = value }
      end,
    })
    state:apply(Actions.osc(7, "file://localhost/private/tmp/kiwi%20work"))
    Assert.equal(#effects, 1)
    Assert.equal(effects[1].kind, "pwd_changed")
    Assert.equal(effects[1].value.host, "localhost")
    Assert.equal(effects[1].value.path, "/private/tmp/kiwi%20work")
    Assert.equal(effects[1].value.uri, "file://localhost/private/tmp/kiwi%20work")
  end,

  shell_metadata_emits_a_cwd_clear_effect_on_terminal_reset = function()
    local effects = {}
    local state = State.new(4, 1, {
      effect_sink = function(kind, value)
        effects[#effects + 1] = { kind = kind, value = value }
      end,
    })
    state:apply(Actions.osc(7, "file://localhost/private/tmp/kiwi"))
    state:reset()
    Assert.equal(#effects, 2)
    Assert.equal(effects[2].kind, "pwd_changed")
    Assert.equal(effects[2].value.cleared, true)
  end,

  shell_metadata_records_bounded_cwd_and_marker_positions_without_terminal_text = function()
    local state = State.new(20, 2)
    local parser = Parser.new(state)
    parser:feed("\27]7;file://host.example/work\27\\\27]133;A\7P> \27]133;B\7echo hi\27]133;C\7\r\nhi\r\n\27]133;D;7\7")
    local view = state.shell:view()
    Assert.equal(view.current_directory.uri, "file://host.example/work")
    Assert.equal(#view.events, 5)
    Assert.equal(view.events[1].kind, "cwd")
    Assert.equal(view.events[2].kind, "prompt")
    Assert.equal(view.events[3].column, 3)
    Assert.equal(view.events[4].kind, "command_executed")
    Assert.equal(view.events[5].exit_status, 7)
    Assert.equal(view.events[5].line_id, state.active_screen.rows[1].line_id)
    Assert.equal(Snapshot.encode(state):find("host%.example"), nil)
  end,

  shell_metadata_rejects_unsafe_cwds_and_malformed_markers_without_overwriting_current_state = function()
    local state = State.new(4, 1)
    state:apply(Actions.osc(7, "file://host.example/work"))
    state:apply(Actions.osc(7, "https://example.test/not-a-cwd"))
    state:apply(Actions.osc(133, "A;unexpected"))
    state:apply(Actions.osc(133, "D;256"))
    state:apply(Actions.osc(133, "E"))
    local view = state.shell:view()
    Assert.equal(view.current_directory.uri, "file://host.example/work")
    Assert.equal(#view.events, 1)
    Assert.equal(view.stats.rejected, 3)
    Assert.equal(view.stats.markers_unknown, 1)
    Assert.equal(state.stats.unknown.osc, 0)
  end,

  shell_metadata_bounds_events_and_resets_with_terminal_state = function()
    local state = State.new(4, 1, { shell_integration = { directory_limit = 1, event_limit = 2 } })
    state:apply(Actions.osc(7, "file://host.example/one"))
    state:apply(Actions.osc(133, "A"))
    state:apply(Actions.osc(7, "file://host.example/two"))
    local view = state.shell:view()
    Assert.equal(#view.events, 2)
    Assert.equal(view.events[1].kind, "prompt")
    Assert.equal(view.events[2].kind, "cwd")
    Assert.equal(view.stats.events_dropped, 1)
    Assert.equal(view.stats.directories_dropped, 1)
    state:reset()
    Assert.equal(#state.shell:view().events, 0)
    Assert.equal(state.shell:view().current_directory, nil)
  end,

  shell_metadata_replays_deterministically_with_logical_timestamps = function()
    with_recording(function(path)
      local recording = Replay.Recorder.new(path)
      recording:resize(8, 2)
      recording:output("\27]7;file://host.example/work\7\27]133;A\7P> \27]133;B\7x\27]133;C\7\r\nx\r\n\27]133;D;0\7")
      recording:close()
      local replayed = State.new(1, 1)
      Replay.apply_file(replayed, path)
      local direct = State.new(1, 1)
      direct:resize(8, 2)
      Parser.new(direct):feed("\27]7;file://host.example/work\7\27]133;A\7P> \27]133;B\7x\27]133;C\7\r\nx\r\n\27]133;D;0\7")
      Assert.equal(Snapshot.encode(replayed), Snapshot.encode(direct))
      Assert.equal(replayed.shell:view().events[5].timestamp, 5)
    end)
  end,
}
