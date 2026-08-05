package.path = table.concat({
  "./src/?.lua",
  "./src/?/init.lua",
  "./tests/?.lua",
  "./tests/?/init.lua",
  package.path,
}, ";")

local cases = require("unit.app.screenshot_scenarios_test")
for _, case in ipairs(cases) do
  local ok, failure = xpcall(case.run, debug.traceback)
  if not ok then
    io.stderr:write("FAIL " .. case.name .. "\n" .. failure .. "\n")
    os.exit(1)
  end
  print("ok " .. case.name)
end
print("passed " .. #cases .. " screenshot scenario tests")
