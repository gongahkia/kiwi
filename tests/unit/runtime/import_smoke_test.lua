local assertions = require("support.assertions")

return {
  {
    name = "core modules import without love",
    run = function()
      local previous_love = rawget(_G, "love")
      _G.love = nil
      local modules = {
        "runtime.errors",
        "runtime.event",
        "terminal.cell",
        "terminal.config",
        "terminal.cursor",
        "terminal.rendition",
        "terminal.row",
        "terminal.screen",
        "terminal.terminal",
        "backend.interface",
        "recording.reader",
      }
      for _, module_name in ipairs(modules) do
        package.loaded[module_name] = nil
        assertions.truthy(require(module_name), "failed import: " .. module_name)
      end
      _G.love = previous_love
    end,
  },
}
