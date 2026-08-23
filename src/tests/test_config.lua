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
  configuration_resolves_system_appearance_to_a_named_theme_before_renderer_use = function()
    local dark = Config.parse("theme = system\ntheme-dark = dracula\ntheme-light = solarized-light\n", "test", nil, { appearance = "dark" })
    local light = Config.parse("theme = system\ntheme-dark = dracula\ntheme-light = solarized-light\n", "test", nil, { appearance = "light" })
    Assert.equal(dark.theme_mode, "system")
    Assert.equal(dark.resolved_appearance, "dark")
    Assert.equal(light.resolved_appearance, "light")
    Assert.equal(Color.unpack(dark.background).red, 0x28)
    Assert.equal(Color.unpack(light.background).red, 0xfd)
  end,
  configuration_preserves_explicit_colours_when_system_appearance_changes = function()
    local dark = Config.parse([[theme = system
theme-dark = dracula
theme-light = solarized-light
foreground = #010203
palette-1 = #a0b0c0
]], "test", nil, { appearance = "dark" })
    local light = Config.parse("appearance = light\n", "platform", dark, { appearance = "light" })
    Assert.equal(light.resolved_appearance, "light")
    Assert.equal(Color.unpack(light.background).red, 0xfd)
    Assert.equal(Color.unpack(light.foreground).red, 1)
    Assert.equal(Color.unpack(light.palette[1]).green, 0xb0)
  end,
  configuration_loads_external_themes_as_bounded_colour_data_only = function()
    local requested
    local config = Config.parse([[theme-file = /trusted/theme.conf
foreground = #010203
]], "test", nil, {
      theme_loader = function(path)
        requested = path
        return Config.parse_theme([[foreground = #112233
background = #445566
palette-1 = #778899
selection-color = #aabbcc
]], path)
      end,
    })
    Assert.equal(requested, "/trusted/theme.conf")
    Assert.equal(config.theme_mode, "external")
    Assert.equal(config.theme_file, "/trusted/theme.conf")
    Assert.equal(Color.unpack(config.background).green, 0x55)
    Assert.equal(Color.unpack(config.palette[1]).blue, 0x99)
    Assert.equal(Color.unpack(config.foreground).red, 0x01)
    Assert.truthy(not pcall(Config.parse_theme, "font-size = 20\nforeground = #112233\nbackground = #445566\n", "test"))
  end,
  configuration_records_bounded_product_keybinding_overrides = function()
    local config = Config.parse([[keybind = ctrl+shift+t = none
keybind = ctrl+alt+t = new-tab
]], "test")
    Assert.equal(#config.keybindings, 2)
    Assert.equal(config.keybindings[1].action, "none")
    Assert.equal(config.keybindings[2].chord, "alt+control+t")
  end,
  configuration_records_bounded_custom_command_palette_entries = function()
    local config = Config.parse([[command-palette-entry = title:"Open a tab", description:"Create a fresh terminal tab.", action:new-tab
command-palette-entry =
command-palette-entry = title:Reload, action:reload-config
]], "test")
    Assert.equal(#config.command_palette_entries, 3)
    local entries = require("kiwi.app.actions").palette_entries(config.command_palette_entries)
    Assert.equal(#entries, 1)
    Assert.equal(entries[1].title, "Reload")
    Assert.truthy(not pcall(Config.parse, "command-palette-entry = title:Unsafe, action:command-palette", "test"))
  end,
  configuration_allows_a_cleared_full_command_palette_and_bounds_directives = function()
    local Actions = require("kiwi.app.actions")
    local entries = { "command-palette-entry =" }
    for index = 1, Actions.maximum_palette_entries do
      entries[#entries + 1] = "command-palette-entry = title:New " .. index .. ", action:new-tab"
    end
    local config = Config.parse(table.concat(entries, "\n"), "test")
    Assert.equal(#Actions.palette_entries(config.command_palette_entries), Actions.maximum_palette_entries)
    local too_many = {}
    for _ = 1, Actions.maximum_palette_directives + 1 do too_many[#too_many + 1] = "command-palette-entry =" end
    Assert.truthy(not pcall(Config.parse, table.concat(too_many, "\n"), "test"))
  end,
  configuration_parses_explicit_osc9_host_effect_policies = function()
    local config = Config.parse("osc9-notifications = system\nosc9-progress = system\n", "test")
    Assert.equal(config.osc9_notifications, "system")
    Assert.equal(config.osc9_progress, "system")
    Assert.truthy(not pcall(Config.parse, "osc9-notifications = always", "test"))
    Assert.truthy(not pcall(Config.parse, "osc9-progress = true", "test"))
  end,
}
