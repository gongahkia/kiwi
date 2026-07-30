local logger = require("src.util.logger")

return function(test)
  test.case("logger emits canonical structured records", function()
    local lines = {}
    local instance = assert(logger.new(function(line)
      lines[#lines + 1] = line
    end))
    local ok, err = instance:write("info", "test", "ready", { id = 7 })
    test.equals(err, nil)
    test.equals(ok, true)
    test.equals(
      lines[1],
      '{"category":"test","fields":{"id":7},"level":"info","message":"ready"}\n'
    )
  end)
end
