local Assert = require("tests.assert")
local Options = require("kiwi.app.options")

return {
  application_options_map_only_the_documented_configuration_flags = function()
    local options = Options.parse({
      "--theme", "dracula",
      "--appearance", "dark",
      "--font-family", "Noto Sans Mono",
      "--font-size", "18",
      "--scrollback-limit", "4000",
      "--shell-integration", "none",
      "--theme-file", "/trusted/theme.conf",
      "--", "/bin/sh", "-l",
    }, function() return nil end, false)
    Assert.equal(#options.configuration_overrides, 7)
    Assert.equal(options.configuration_overrides[1].key, "theme")
    Assert.equal(options.configuration_overrides[1].value, "dracula")
    Assert.equal(options.configuration_overrides[7].key, "theme-file")
    Assert.equal(options.command[1], "/bin/sh")
    Assert.equal(options.command[2], "-l")
  end,
  application_options_reject_missing_unknown_or_control_configuration_values = function()
    Assert.truthy(not pcall(Options.parse, { "--theme" }, function() return nil end, false))
    Assert.truthy(not pcall(Options.parse, { "--theme", "bad\nname" }, function() return nil end, false))
    Assert.truthy(not pcall(Options.parse, { "--unknown" }, function() return nil end, false))
  end,
  application_options_preserve_the_existing_smoke_layout_policy = function()
    local options = Options.parse({ "--toolbar-smoke", "--automation-smoke" }, function() return nil end, true)
    Assert.equal(options.toolbar_smoke, true)
    Assert.equal(options.automation_smoke, true)
    Assert.equal(options.layout_persistence, false)
    Assert.equal(options.layout_restore, false)
    Assert.equal(options.release_mode, true)
  end,
}
