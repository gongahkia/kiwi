local Assert = require("tests.assert")
local Color = require("kiwi.renderer.color")
local Config = require("kiwi.config")

return {
  configuration_parses_a_bounded_theme_and_explicit_overrides = function()
    local config = Config.parse([[ 
      # one comment
      theme = nord
      font-family = "Noto Sans Mono"
      font-size = 18
      ligatures = true
      osc52-write = true
      resize-reflow = false
      palette-1 = #010203
      foreground = #112233
    ]], "test")
    Assert.equal(config.theme, "nord")
    Assert.equal(config.font_family, "Noto Sans Mono")
    Assert.equal(config.font_size, 18)
    Assert.equal(config.ligatures, true)
    Assert.equal(config.osc52_write, true)
    Assert.equal(config.resize_reflow, false)
    Assert.equal(Color.unpack(config.palette[1]).green, 2)
    Assert.equal(Color.unpack(config.foreground).red, 0x11)
  end,
  configuration_rejects_unknown_or_invalid_values = function()
    Assert.truthy(not pcall(Config.parse, "unknown = true", "test"))
    Assert.truthy(not pcall(Config.parse, "font-size = 0", "test"))
    Assert.truthy(not pcall(Config.parse, "background = teal", "test"))
    Assert.truthy(not pcall(Config.parse, "theme = unknown", "test"))
  end,
  configuration_environment_overrides_file_values_without_mutating_other_values = function()
    local config = Config.parse("font-size = 14\nligatures = false\n", "test")
    local values = {
      KIWI_FONT_PX = "22",
      KIWI_LIGATURES = "1",
      KIWI_SCROLLBACK = "3000",
    }
    Config.apply_environment(config, function(name) return values[name] end)
    Assert.equal(config.font_size, 22)
    Assert.equal(config.ligatures, true)
    Assert.equal(config.scrollback_limit, 3000)
    Assert.equal(config.font_family, "monospace")
  end,
  configuration_default_path_prefers_xdg = function()
    Assert.equal(Config.default_path(function(name)
      return ({ XDG_CONFIG_HOME = "/tmp/xdg", HOME = "/tmp/home" })[name]
    end), "/tmp/xdg/kiwi/config")
  end,
}
