local suites = {
  "tests.test_damage",
  "tests.test_build",
  "tests.test_doctor",
  "tests.test_paths",
  "tests.test_library",
  "tests.test_config",
  "tests.test_configuration_reload",
  "tests.test_configuration_watch",
  "tests.test_reload_bench",
  "tests.test_filesystem",
  "tests.test_app_options",
  "tests.test_actions",
  "tests.test_interaction_actions",
  "tests.test_product_action_dispatcher",
  "tests.test_host_effects",
  "tests.test_compatibility",
  "tests.test_compatibility_qualification",
  "tests.test_application_protocols",
  "tests.test_workspace",
  "tests.test_window_manager",
  "tests.test_layout_store",
  "tests.test_live_window_manager",
  "tests.test_host_controller",
  "tests.test_terminal",
  "tests.test_synthetic",
  "tests.test_utf8",
  "tests.test_unicode",
  "tests.test_state",
  "tests.test_terminal_session",
  "tests.test_text_state",
  "tests.test_text_fixtures",
  "tests.test_text_layout",
  "tests.test_text_backend",
  "tests.test_text_lab",
  "tests.test_accessibility",
  "tests.test_atspi_projection",
  "tests.test_harfbuzz_diff",
  "tests.test_parser",
  "tests.test_kitty_graphics",
  "tests.test_animated_images",
  "tests.test_kitty_placements",
  "tests.test_kitty_image_script",
  "tests.test_kitty_image_renderer",
  "tests.test_prepared_images",
  "tests.test_fuzz",
  "tests.test_replay",
  "tests.test_reflow",
  "tests.test_diagnostics",
  "tests.test_conformance",
  "tests.test_parser_bench",
  "tests.test_pipeline_bench",
  "tests.test_longrun",
  "tests.test_pacing",
  "tests.test_poll_schedule",
  "tests.test_pacing_budget",
  "tests.test_power",
  "tests.test_device_soak",
  "tests.test_text_bench",
  "tests.test_write_bench",
  "tests.test_glyph_fallback",
  "tests.test_keyboard",
  "tests.test_input_correlation",
  "tests.test_mouse",
  "tests.test_scrollback_wheel",
  "tests.test_scrollbar",
  "tests.test_selection",
  "tests.test_history_actions",
  "tests.test_selection_pointer",
  "tests.test_selection_renderer",
  "tests.test_clipboard",
  "tests.test_hyperlink",
  "tests.test_shell_integration",
  "tests.test_shell_scripts",
  "tests.test_shell_launcher",
  "tests.test_kiwi_ssh",
  "tests.test_command_regions",
  "tests.test_command_region_retention",
  "tests.test_compositor",
  "tests.test_command_region_navigation",
  "tests.test_command_region_renderer",
  "tests.test_command_region_extension_sample",
  "tests.test_composition_spike",
  "tests.test_search",
  "tests.test_search_input",
  "tests.test_vi",
  "tests.test_vi_input",
  "tests.test_regex",
  "tests.test_search_renderer",
  "tests.test_atlas",
  "tests.test_glyph_cache",
  "tests.test_freetype",
  "tests.test_font_styles",
  "tests.test_underline",
  "tests.test_decoration",
  "tests.test_decoration_layout",
  "tests.test_glyph_shader",
  "tests.test_packing",
  "tests.test_render_model",
  "tests.test_prepared_frame",
  "tests.test_gtk_gl_consumer",
  "tests.test_gtk_gl_controller",
  "tests.test_gtk_native_tab_group",
  "tests.test_pass_registry",
  "tests.test_pass_api",
  "tests.test_extensions",
  "tests.test_extension_sample",
  "tests.test_pass_metrics",
  "tests.test_pass_budgets",
  "tests.test_invalidation",
  "tests.test_inspector",
  "tests.test_gpu_timing",
  "tests.test_gpu_recovery",
  "tests.test_timestamp_probe",
  "tests.test_renderer_resources",
  "tests.test_shader_loader",
  "tests.test_shader_reloader",
  "tests.test_color",
  "tests.test_json",
  "tests.test_stats",
}

-- These suites exercise the product model without loading graphics, fonts or
-- the native PTY bridge. Keep the full suite as the release gate.
local core_names = [[
damage paths library config configuration_reload configuration_watch app_options interaction_actions product_action_dispatcher
host_effects compatibility workspace window_manager layout_store terminal utf8
unicode state terminal_session text_state text_fixtures parser reflow
fuzz poll_schedule input_correlation mouse scrollback_wheel scrollbar
selection history_actions selection_pointer clipboard shell_integration
command_regions command_region_retention compositor command_region_navigation
search search_input vi vi_input regex packing render_model gtk_native_tab_group pass_registry pass_api
extensions pass_metrics pass_budgets invalidation gpu_timing gpu_recovery
color json stats atlas glyph_cache application_protocols underline decoration
]]
local core = {}
for name in core_names:gmatch("%S+") do core["tests.test_" .. name] = true end
local core_only = arg[1] == "--core"
local requested = {}
if core_only then
  assert(#arg == 1, "--core does not accept individual suites")
  -- Guard the promise made by make test-core, even on fully provisioned hosts.
  require("ffi").load = function(name) error("core test attempted native loading: " .. tostring(name)) end
else
  local known = {}
  for _, name in ipairs(suites) do known[name] = true end
  for _, name in ipairs(arg) do
    name = name:match("^tests%.") and name or "tests.test_" .. name
    assert(known[name], "unknown test suite: " .. name)
    requested[name] = true
  end
end

local total, suite_count = 0, 0
for _, module in ipairs(suites) do
  if (core_only and core[module]) or (not core_only and (#arg == 0 or requested[module])) then
    suite_count = suite_count + 1
    local suite = require(module)
    local names = {}
    for name in pairs(suite) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      total = total + 1
      local ok, err = xpcall(suite[name], debug.traceback)
      if not ok then
        io.stdout:flush()
        io.stderr:write("FAIL ", name, "\n", err, "\n")
        os.exit(1)
      end
      io.stdout:write("PASS ", name, "\n")
    end
  end
end
io.stdout:write(string.format("%d deterministic LuaJIT tests passed across %d suites%s.\n", total, suite_count, core_only and " (core; native loading disabled)" or ""))
