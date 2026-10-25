local Assert = require("tests.assert")
local Config = require("kiwi.config")
local Watch = require("kiwi.app.configuration_watch")
local Utf8 = require("kiwi.terminal.utf8")

return {
  configuration_equivalence_ignores_runtime_ownership_but_checks_nested_settings = function()
    local original, same = Config.parse(""), Config.parse("# just a comment")
    original.host_effects = { configuration = original }
    original.path = "/previous/path"
    Assert.truthy(Config.equivalent(original, same))
    same.palette[42] = 123
    Assert.equal(Config.equivalent(original, same), false)
    same = Config.parse("keybind = ctrl+a = new-tab")
    Assert.equal(Config.equivalent(original, same), false)
    Assert.equal(Config.equivalent(same, original), false)
  end,
  configuration_watch_coalesces_edits_and_does_not_repeat_failed_attempts = function()
    local watch = Watch.new()
    Assert.equal(watch:ready(10), false)
    watch:observe(true, 10)
    Assert.equal(watch:ready(10.1), false)
    watch:observe(true, 10.15)
    Assert.equal(watch:ready(10.25), false)
    watch:observe(false, 10.3)
    Assert.equal(watch:ready(10.36), true)
    watch:set_error("invalid configuration")
    Assert.equal(watch:ready(100), false)
    watch:observe(true, 101)
    Assert.equal(watch:ready(101.21), true)
    watch:observe(true, 102)
    watch:acknowledge()
    Assert.equal(watch:ready(103), false)
  end,
  configuration_errors_are_bounded_valid_utf8_and_clear_on_recovery = function()
    local watch = Watch.new()
    watch:set_error("src/kiwi/config.lua:123: configuration line 2: " .. string.rep("界", 200) .. "\27\0\nstack trace")
    local title = watch:title("shell")
    Assert.truthy(title:find("Configuration error: configuration line 2:", 1, true))
    Assert.equal(title:find("src/kiwi", 1, true), nil)
    Assert.equal(title:find("stack trace", 1, true), nil)
    Assert.truthy(#title < 600)
    local decoder = Utf8.Decoder.new(function(_, _, invalid) Assert.equal(not invalid, true) end)
    for index = 1, #title do decoder:feed_byte(title:byte(index)) end
    decoder:finish()
    watch:set_error("bad\0\27value")
    Assert.equal(watch.error, "bad  value")
    watch:set_error(nil)
    Assert.equal(watch:title("shell"), "shell")
  end,
  live_configuration_reload_defaults_on_and_accepts_explicit_opt_out = function()
    Assert.equal(Config.parse("").live_config_reload, true)
    Assert.equal(Config.parse("live-config-reload = false").live_config_reload, false)
    Assert.equal(pcall(Config.parse, "live-config-reload = maybe"), false)
  end,
  configuration_load_reports_theme_dependencies_even_when_missing = function()
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write("theme-file = /missing/kiwi-test-theme\n"); file:close()
    local seen = {}
    local ok, message = pcall(Config.load, path, function() end, {
      on_dependency = function(dependency) seen[#seen + 1] = dependency end,
      theme_loader = function() error("theme absent") end,
    })
    os.remove(path)
    Assert.equal(ok, false)
    Assert.truthy(tostring(message):find("theme absent", 1, true))
    Assert.equal(seen[1], path)
    Assert.equal(seen[2], "/missing/kiwi-test-theme")
  end,
  configuration_load_watches_absent_default_paths_and_cli_theme_overrides = function()
    local seen = {}
    Config.load(nil, function(name) if name == "HOME" then return "/nonexistent/kiwi-test-user" end end, {
      on_dependency = function(path) seen[#seen + 1] = path end,
      command_line_overrides = { { key = "theme-file", value = "/theme/from/cli" } },
      theme_loader = function() return Config.parse_theme("background = #123456\nforeground = #abcdef") end,
    })
    Assert.equal(seen[1], "/nonexistent/kiwi-test-user/.config/kiwi/config")
    Assert.equal(seen[#seen], "/theme/from/cli")
  end,
}
