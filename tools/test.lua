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
  "unit.runtime.errors_test",
  "unit.runtime.event_test",
  "unit.runtime.import_smoke_test",
  "unit.terminal.cell_test",
  "unit.terminal.config_test",
  "unit.terminal.cursor_test",
  "unit.terminal.digest_test",
  "unit.terminal.fixtures_test",
  "unit.terminal.parser_test",
  "unit.terminal.rendition_test",
  "unit.terminal.row_test",
  "unit.terminal.scrollback_test",
  "unit.terminal.screen_test",
  "unit.terminal.terminal_test",
  "unit.terminal.utf8_test",
  "unit.backend.interface_test",
  "unit.recording.reader_test",
  "unit.renderer.renderer_test",
  "unit.effects.effect_test",
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
