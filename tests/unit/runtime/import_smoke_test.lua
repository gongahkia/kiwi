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
        "runtime.coordinator",
        "terminal.cell",
        "terminal.config",
        "terminal.cursor",
        "terminal.digest",
        "terminal.parser",
        "terminal.rendition",
        "terminal.row",
        "terminal.screen",
        "terminal.scrollback",
        "terminal.terminal",
        "terminal.utf8",
        "backend.interface",
        "backend.replay",
        "recording.binary",
        "recording.checksum",
        "recording.checkpoint",
        "recording.format",
        "recording.frames",
        "recording.inspect",
        "recording.metadata",
        "recording.reader",
        "recording.writer",
        "renderer.metrics",
        "renderer.colour",
        "renderer.glyph_cache",
        "renderer.grid",
        "renderer.love_font",
        "renderer.renderer",
      }
      for _, module_name in ipairs(modules) do
        package.loaded[module_name] = nil
        assertions.truthy(require(module_name), "failed import: " .. module_name)
      end
      _G.love = previous_love
    end,
  },
}
