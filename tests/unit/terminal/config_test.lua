local assertions = require("support.assertions")
local Config = require("terminal.config")

return {
  {
    name = "terminal config applies semantic defaults",
    run = function()
      local config = assert(Config.new())
      assertions.equal(80, config.columns)
      assertions.equal("stanczyk-basic-v1", config.compatibility_profile)
      assertions.equal(24, config.rows)
      assertions.equal(1000, config.scrollback_limit)
    end,
  },
  {
    name = "terminal config accepts bounded semantic values",
    run = function()
      local config = assert(Config.new({
        columns = 120,
        compatibility_profile = "stanczyk-basic-v1",
        rows = 40,
        scrollback_limit = 0,
      }))
      assertions.equal(120, config.columns)
      assertions.equal(40, config.rows)
      assertions.equal(0, config.scrollback_limit)
    end,
  },
  {
    name = "terminal config rejects invalid semantic values",
    run = function()
      local invalid_configs = {
        { columns = 0 },
        { columns = false },
        { columns = 1.5 },
        { rows = 1001 },
        { scrollback_limit = -1 },
        { scrollback_limit = 100001 },
        { compatibility_profile = "xterm" },
        { unexpected = true },
      }
      for _, options in ipairs(invalid_configs) do
        local config, error_value = Config.new(options)
        assertions.falsy(config)
        assertions.equal("config_error", error_value.kind)
      end
    end,
  },
  {
    name = "terminal config cannot be changed through normal assignment",
    run = function()
      local config = assert(Config.new({ columns = 100 }))
      local ok = pcall(function()
        config.columns = 120
      end)
      assertions.falsy(ok)
      assertions.equal(100, config.columns)
      assertions.equal(false, getmetatable(config))
    end,
  },
}
