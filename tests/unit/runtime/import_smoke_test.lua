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
        "shell.dispatcher",
        "shell.history",
        "shell.output",
        "shell.registry",
        "shell.session",
        "shell.tokenizer",
        "effects.effect",
        "effects.clean",
        "effects.crt",
        "effects.kinetic",
        "effects.host",
        "effects.manifest",
        "effects.random",
        "effects.subscriptions",
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
        "renderer.clean",
        "renderer.colour",
        "renderer.dpi",
        "renderer.effect_canvas",
        "renderer.glyph_cache",
        "renderer.glyph_resolver",
        "renderer.grid",
        "renderer.love_font",
        "renderer.renderer",
        "renderer.snapshot",
      }
      for _, module_name in ipairs(modules) do
        package.loaded[module_name] = nil
        assertions.truthy(require(module_name), "failed import: " .. module_name)
      end
      _G.love = previous_love
    end,
  },
}
