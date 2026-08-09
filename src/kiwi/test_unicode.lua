local suite = require("tests.test_unicode")

local total = 0
for name, test in pairs(suite) do
  total = total + 1
  local ok, err = xpcall(test, debug.traceback)
  if not ok then
    io.stderr:write("FAIL ", name, "\n", err, "\n")
    os.exit(1)
  end
  io.stdout:write("PASS ", name, "\n")
end
io.stdout:write(string.format("%d Unicode tests passed.\n", total))
