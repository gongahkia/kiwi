local Assert = require("tests.assert")
local Color = require("kiwi.renderer.color")
local Config = require("kiwi.config")
local Filesystem = require("kiwi.platform.filesystem")

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
      macos-applescript = false
      palette-1 = #010203
      foreground = #112233
    ]], "test")
    Assert.equal(config.theme, "nord")
    Assert.equal(config.font_family, "Noto Sans Mono")
    Assert.equal(config.font_size, 18)
    Assert.equal(config.ligatures, true)
    Assert.equal(config.osc52_write, true)
    Assert.equal(config.shell_integration, "none")
    Assert.equal(config.macos_applescript, false)
    Assert.equal(Color.unpack(config.palette[1]).green, 2)
    Assert.equal(Color.unpack(config.foreground).red, 0x11)
  end,
  configuration_rejects_unknown_or_invalid_values = function()
    Assert.truthy(not pcall(Config.parse, "unknown = true", "test"))
    Assert.truthy(not pcall(Config.parse, "font-size = 0", "test"))
    Assert.truthy(not pcall(Config.parse, "background = teal", "test"))
    Assert.truthy(not pcall(Config.parse, "theme = unknown", "test"))
    Assert.truthy(not pcall(Config.parse, "shell-integration = always", "test"))
    Assert.truthy(not pcall(Config.parse, "macos-applescript = enabled", "test"))
  end,
  configuration_defaults_to_bounded_macos_applescript_actions = function()
    Assert.equal(Config.parse("", "test").macos_applescript, true)
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
  configuration_command_line_overrides_are_bounded_and_take_precedence = function()
    local config = Config.load(nil, function(name)
      return ({ KIWI_FONT_PX = "16" })[name]
    end, {
      appearance = "dark",
      command_line_overrides = {
        { key = "theme", value = "dracula" },
        { key = "font-size", value = "18" },
        { key = "shell-integration", value = "none" },
      },
    })
    Assert.equal(config.theme, "dracula")
    Assert.equal(config.font_size, 18)
    Assert.equal(config.shell_integration, "none")
    Assert.equal(Color.unpack(config.background).red, 0x28)
    Assert.truthy(not pcall(Config.apply_command_line, config, { { key = "keybind", value = "ctrl+a = new-tab" } }))
    Assert.truthy(not pcall(Config.apply_command_line, config, { { key = "theme", value = "bad\nvalue" } }))
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
  configuration_selects_the_effective_or_highest_precedence_edit_path = function()
    local environment = function(name)
      return ({ XDG_CONFIG_HOME = "/tmp/xdg", HOME = "/tmp/home" })[name]
    end
    Assert.equal(Config.edit_path(nil, "/tmp/loaded", environment, "OSX"), "/tmp/loaded")
    Assert.equal(Config.edit_path("relative-config", nil, environment, "OSX"), "relative-config")
    Assert.equal(Config.edit_path(nil, nil, environment, "Linux"), "/tmp/xdg/kiwi/config")
    Assert.equal(Config.edit_path(nil, nil, environment, "OSX"), "/tmp/home/Library/Application Support/io.github.gongahkia.kiwi/config")
    Assert.equal(Config.edit_path(nil, nil, function() return nil end, "Linux"), nil)
  end,
  configuration_edit_template_is_parseable_and_comment_only = function()
    Assert.equal(Config.edit_template:sub(1, 1), "#")
    local config = Config.parse(Config.edit_template, "template")
    Assert.equal(config.theme, "kiwi")
    Assert.equal(config.font_size, 20)
  end,
  configuration_initialization_creates_parent_directories_and_never_replaces_a_file = function()
    local directories = {}
    local created_path
    local created_contents
    local initialized, status = Filesystem.ensure_new_file("/tmp/kiwi/config", "# template\n", {
      mkdir = function(path)
        directories[#directories + 1] = path
        return true, "exists"
      end,
      create = function(path, contents)
        created_path = path
        created_contents = contents
        return true, "created"
      end,
    })
    Assert.truthy(initialized)
    Assert.equal(status, "created")
    Assert.equal(table.concat(directories, ","), "/tmp,/tmp/kiwi")
    Assert.equal(created_path, "/tmp/kiwi/config")
    Assert.equal(created_contents, "# template\n")
    local retained, retained_status = Filesystem.ensure_new_file("/tmp/kiwi/config", "# replacement\n", {
      mkdir = function() return true, "exists" end,
      create = function() return true, "exists" end,
    })
    Assert.truthy(retained)
    Assert.equal(retained_status, "exists")
    Assert.truthy(not pcall(Filesystem.ensure_new_file, "relative/config", "# template\n"))
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
keybind = ctrl+a > n = new-window
]], "test")
    Assert.equal(#config.keybindings, 3)
    Assert.equal(config.keybindings[1].action, "none")
    Assert.equal(config.keybindings[2].chord, "alt+control+t")
    Assert.equal(config.keybindings[3].chord, "control+a>n")
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
