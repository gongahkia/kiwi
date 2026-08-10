local Assert = require("tests.assert")
local Doctor = require("kiwi.doctor")

local function fixture(options)
  options = options or {}
  local values = options.values or {}
  return Doctor.collect({
    build = { release_mode = false, revision = "revision", version = "0.1.0" },
    command = function() return "Linux 6.16" end,
    getenv = function(name) return values[name] end,
    gpu_probe = options.gpu_probe or function()
      return { status = "available", adapter = { backend = "Vulkan", device = "bounded adapter", vendor = "bounded vendor" }, capabilities = { timestamp_query = { enabled = false, reason = "disabled by configuration" } } }
    end,
    path_exists = function() return true end,
    root = "/fixture",
  })
end

return {
  doctor_schema_is_stable_bounded_and_excludes_sensitive_configuration_values = function()
    local report = fixture({ values = {
      KIWI_FONT = "/home/user/private-font.ttf",
      KIWI_RENDER_EXTENSIONS = "private.module,another.private.module",
      KIWI_SCROLLBACK = "4000",
    } })
    local encoded = Doctor.encode(report)
    Assert.equal(report.schema_version, 1)
    Assert.equal(report.configuration.extensions.requested_count, 2)
    Assert.equal(report.configuration.fonts.custom_path_configured, true)
    Assert.equal(report.privacy.terminal_content, "excluded")
    Assert.equal(encoded:find("private%-font", 1, false), nil)
    Assert.equal(encoded:find("private%.module", 1, false), nil)
    Assert.truthy(#encoded <= Doctor.MAX_BUNDLE_BYTES)
  end,
  doctor_makes_unavailable_native_and_live_session_state_explicit = function()
    local report = fixture({ gpu_probe = function() return { status = "unavailable", reason = "no display" } end })
    Assert.equal(report.gpu.status, "unavailable")
    Assert.equal(report.gpu.reason, "no display")
    Assert.equal(report.renderer.pass_state.status, "unavailable")
    Assert.equal(report.terminal.feature_state.status, "unavailable")
    Assert.equal(report.terminal.known_features.truecolour_terminfo.status, "unavailable")
    Assert.truthy(Doctor.format(report):match("gpu: status=unavailable") ~= nil)
  end,
}
