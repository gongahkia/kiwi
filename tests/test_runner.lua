package.path = "./?.lua;./?/init.lua;" .. package.path

local test = require("tests.test")
local modules = {
  "tests.unit.ordered_test",
  "tests.unit.id_allocator_test",
  "tests.unit.prng_test",
  "tests.unit.serializer_test",
  "tests.unit.hash_test",
  "tests.unit.logger_test",
  "tests.unit.lexer_test",
}

for _, module_name in ipairs(modules) do
  local register = require(module_name)
  register(test)
end

os.exit(test.run())
