package.path = table.concat({
  "./src/?.lua",
  "./src/?/init.lua",
  "./tests/?.lua",
  "./tests/?/init.lua",
  package.path,
}, ";")

local seed = os.getenv("STANCZYK_TEST_SEED") or "20260730"
if not seed:match("^%d+$") then
  io.stderr:write("invalid STANCZYK_TEST_SEED: expected unsigned decimal integer\n")
  os.exit(2)
end

local numeric_seed = tonumber(seed)
if not numeric_seed or numeric_seed > 2147483647 then
  io.stderr:write("invalid STANCZYK_TEST_SEED: expected value from 0 to 2147483647\n")
  os.exit(2)
end

math.randomseed(numeric_seed)
print("test seed: " .. seed)

local modules = {
  "property.terminal_chunking_test",
  "property.parser_recovery_test",
  "property.recording_resize_test",
  "property.effect_lifecycle_test",
  "property.effect_random_test",
  "property.effect_subscriptions_test",
  "unit.runtime.errors_test",
  "unit.runtime.event_test",
  "unit.runtime.coordinator_test",
  "unit.runtime.recording_session_test",
  "unit.runtime.import_smoke_test",
  "unit.app.standalone_test",
  "unit.terminal.cell_test",
  "unit.terminal.config_test",
  "unit.terminal.cursor_test",
  "unit.terminal.digest_test",
  "unit.terminal.fixtures_test",
  "unit.terminal.golden_test",
  "unit.terminal.model_test",
  "unit.terminal.parser_test",
  "unit.terminal.rendition_test",
  "unit.terminal.row_test",
  "unit.terminal.resize_test",
  "unit.terminal.scrollback_test",
  "unit.terminal.screen_test",
  "unit.terminal.terminal_test",
  "unit.terminal.utf8_test",
  "unit.backend.interface_test",
  "unit.backend.replay_test",
  "unit.recording.binary_test",
  "unit.recording.checksum_test",
  "unit.recording.checkpoint_test",
  "unit.recording.format_test",
  "unit.recording.frames_test",
  "unit.recording.inspect_test",
  "unit.recording.metadata_test",
  "unit.recording.reader_test",
  "unit.recording.writer_test",
  "unit.renderer.renderer_test",
  "unit.renderer.canvas_hooks_test",
  "unit.effects.manifest_test",
  "unit.effects.clean_test",
  "unit.effects.crt_test",
  "unit.effects.kinetic_test",
  "unit.effects.random_test",
  "unit.effects.effect_test",
  "unit.effects.host_test",
}

local total = 0
for _, module_name in ipairs(modules) do
  local cases = require(module_name)
  for _, case in ipairs(cases) do
    total = total + 1
    local ok, failure = xpcall(case.run, debug.traceback)
    if not ok then
      io.stderr:write("FAIL " .. case.name .. "\n" .. failure .. "\n")
      os.exit(1)
    end
    print("ok " .. case.name)
  end
end

print("passed " .. total .. " tests")
