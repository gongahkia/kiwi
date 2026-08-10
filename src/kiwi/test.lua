local tests = {
  require("tests.test_damage"),
  require("tests.test_terminal"),
  require("tests.test_synthetic"),
  require("tests.test_utf8"),
  require("tests.test_unicode"),
  require("tests.test_state"),
  require("tests.test_text_state"),
  require("tests.test_text_fixtures"),
  require("tests.test_text_layout"),
  require("tests.test_harfbuzz_diff"),
  require("tests.test_parser"),
  require("tests.test_replay"),
  require("tests.test_diagnostics"),
  require("tests.test_conformance"),
  require("tests.test_parser_bench"),
  require("tests.test_pipeline_bench"),
  require("tests.test_text_bench"),
  require("tests.test_write_bench"),
  require("tests.test_glyph_fallback"),
  require("tests.test_keyboard"),
  require("tests.test_atlas"),
  require("tests.test_freetype"),
  require("tests.test_packing"),
  require("tests.test_pass_registry"),
  require("tests.test_pass_api"),
  require("tests.test_extensions"),
  require("tests.test_pass_metrics"),
  require("tests.test_invalidation"),
  require("tests.test_inspector"),
  require("tests.test_gpu_timing"),
  require("tests.test_timestamp_probe"),
  require("tests.test_renderer_resources"),
  require("tests.test_shader_loader"),
  require("tests.test_shader_reloader"),
  require("tests.test_color"),
  require("tests.test_json"),
  require("tests.test_stats"),
}

local total = 0
for _, suite in ipairs(tests) do
  for name, test in pairs(suite) do
    total = total + 1
    local ok, err = xpcall(test, debug.traceback)
    if not ok then
      io.stderr:write("FAIL ", name, "\n", err, "\n")
      os.exit(1)
    end
    io.stdout:write("PASS ", name, "\n")
  end
end

io.stdout:write(string.format("%d deterministic LuaJIT tests passed.\n", total))
