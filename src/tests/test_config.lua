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
      shell-integration = none
      palette-1 = #010203
      foreground = #112233
    ]], "test")
    Assert.equal(config.theme, "nord")
    Assert.equal(config.font_family, "Noto Sans Mono")
    Assert.equal(config.font_size, 18)
    Assert.equal(config.ligatures, true)
    Assert.equal(config.osc52_write, true)
    Assert.equal(config.shell_integration, "none")
    Assert.equal(Color.unpack(config.palette[1]).green, 2)
    Assert.equal(Color.unpack(config.foreground).red, 0x11)
  end,
  configuration_rejects_unknown_or_invalid_values = function()
    Assert.truthy(not pcall(Config.parse, "unknown = true", "test"))
    Assert.truthy(not pcall(Config.parse, "font-size = 0", "test"))
    Assert.truthy(not pcall(Config.parse, "background = teal", "test"))
    Assert.truthy(not pcall(Config.parse, "theme = unknown", "test"))
    Assert.truthy(not pcall(Config.parse, "shell-integration = always", "test"))
  end,
  configuration_environment_overrides_file_values_without_mutating_other_values = function()
    local config = Config.parse("font-size = 14\nligatures = false\n", "test")
    local values = {
      KIWI_FONT_PX = "22",
      KIWI_LIGATURES = "1",
      KIWI_SCROLLBACK = "3000",
      KIWI_SHELL_INJECTION = "none",
    }
    Config.apply_environment(config, function(name) return values[name] end)
    Assert.equal(config.font_size, 22)
    Assert.equal(config.ligatures, true)
    Assert.equal(config.scrollback_limit, 3000)
    Assert.equal(config.font_family, "monospace")
    Assert.equal(config.shell_integration, "none")
  end,
  configuration_default_path_prefers_xdg = function()
    Assert.equal(Config.default_path(function(name)
      return ({ XDG_CONFIG_HOME = "/tmp/xdg", HOME = "/tmp/home" })[name]
    end), "/tmp/xdg/kiwi/config")
  end,
  configuration_uses_mac_application_support_after_xdg = function()
    local paths = Config.default_paths(function(name)
      return ({ XDG_CONFIG_HOME = "/tmp/xdg", HOME = "/tmp/home" })[name]
    end, "OSX")
    Assert.equal(paths[1], "/tmp/xdg/kiwi/config")
    Assert.equal(paths[2], "/tmp/home/Library/Application Support/io.github.gongahkia.kiwi/config")
  end,
  configuration_later_sources_preserve_prior_values_without_resetting_them = function()
    local base = Config.parse("theme = dracula\nfont-size = 15\n", "base")
    local override = Config.parse("font-family = \"Noto Sans Mono\"\n", "override", base)
    Assert.equal(override.theme, "dracula")
    Assert.equal(override.font_size, 15)
    Assert.equal(override.font_family, "Noto Sans Mono")
    Assert.equal(Color.unpack(override.background).blue, 0x36)
  end,
  configuration_exposes_the_expanded_builtin_theme_catalogue = function()
    local names = table.concat(Config.theme_names(), ",")
    Assert.truthy(names:find("catppuccin%-mocha") ~= nil)
    Assert.truthy(names:find("dracula") ~= nil)
    Assert.truthy(names:find("gruvbox%-dark") ~= nil)
    Assert.truthy(names:find("solarized%-light") ~= nil)
    Assert.truthy(names:find("tokyo%-night") ~= nil)
  end,
}
