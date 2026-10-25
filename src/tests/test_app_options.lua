local Assert = require("tests.assert")
local Options = require("kiwi.app.options")

return {
  explicit_launch_intent_cannot_restore_or_overwrite_saved_shells = function()
    local configured = function() return "1" end
    for _, arguments in ipairs({ { "--", "sh", "-c", "printf ok" }, { "--working-directory", "/tmp/work dir" } }) do
      local options = Options.parse(arguments, configured)
      Assert.equal(options.layout_restore, false)
      Assert.equal(options.layout_persistence, false)
    end
    local options = Options.parse({}, function() return nil end)
    Assert.equal(options.layout_restore, true)
    Assert.equal(options.layout_persistence, true)
  end,
  launch_options_validate_paths_and_preserve_command_arguments = function()
    for _, arguments in ipairs({ { "--" }, { "--", "" }, { "--", "sh\0bad" },
      { "--working-directory", "relative" }, { "--working-directory", "/bad\npath" },
      { "--working-directory", "/" .. string.rep("a", 2048) } }) do
      Assert.equal(pcall(Options.parse, arguments), false)
    end
    local options = Options.parse({ "--working-directory", "/tmp/work dir", "--", "sh", "-c", "printf 'a\nb'", "" })
    Assert.equal(options.initial_cwd, "/tmp/work dir")
    Assert.equal(options.command[3], "printf 'a\nb'")
    Assert.equal(options.command[4], "")
    Assert.equal(Options.parse({ "-h" }).help, true)
    Assert.equal(Options.parse({ "--help" }).help, true)
  end,
  application_options_map_only_the_documented_configuration_flags = function()
    local options = Options.parse({
      "--theme", "dracula",
      "--appearance", "dark",
      "--font-family", "Noto Sans Mono",
      "--font-size", "18",
      "--scrollback-limit", "4000",
      "--scrollbar", "never",
      "--shell-integration", "none",
      "--theme-file", "/trusted/theme.conf",
      "--", "/bin/sh", "-l",
    }, function() return nil end, false)
    Assert.equal(#options.configuration_overrides, 8)
    Assert.equal(options.configuration_overrides[1].key, "theme")
    Assert.equal(options.configuration_overrides[1].value, "dracula")
    Assert.equal(options.configuration_overrides[6].key, "scrollbar")
    Assert.equal(options.configuration_overrides[8].key, "theme-file")
    Assert.equal(options.command[1], "/bin/sh")
    Assert.equal(options.command[2], "-l")
  end,
  application_options_reject_missing_unknown_or_control_configuration_values = function()
    Assert.truthy(not pcall(Options.parse, { "--theme" }, function() return nil end, false))
    Assert.truthy(not pcall(Options.parse, { "--theme", "bad\nname" }, function() return nil end, false))
    Assert.truthy(not pcall(Options.parse, { "--unknown" }, function() return nil end, false))
  end,
  application_options_preserve_the_existing_smoke_layout_policy = function()
    local options = Options.parse({ "--toolbar-smoke", "--cwd-smoke", "--automation-smoke" }, function() return nil end, true)
    Assert.equal(options.toolbar_smoke, true)
    Assert.equal(options.cwd_smoke, true)
    Assert.equal(options.automation_smoke, true)
    Assert.equal(options.layout_persistence, false)
    Assert.equal(options.layout_restore, false)
    Assert.equal(options.release_mode, true)
  end,
}
