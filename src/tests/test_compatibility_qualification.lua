local Assert = require("tests.assert")
local Qualification = require("kiwi.compatibility.qualification")

local function doctor()
  return {
    environment = { architecture = "x64", kernel = "Linux 1", operating_system = "Linux", session = "wayland" },
    gpu = { status = "available" },
    privacy = { clipboard_content = "excluded", terminal_content = "excluded" },
  }
end

return {
  compatibility_qualification_report_is_bounded_and_excludes_terminal_content = function()
    local report = Qualification.collect({
      { name = "neovim", status = "passed", detail = "Kitty keyboard negotiation replayed cleanly" },
      { name = "clipboard", status = "manual", detail = string.rep("x", 300) },
    }, { doctor = doctor() })
    Assert.equal(report.schema_version, 1)
    Assert.equal(report.kind, "kiwi-daily-driver-compatibility")
    Assert.equal(report.checks[1].name, "neovim")
    Assert.equal(report.checks[2].status, "manual")
    Assert.truthy(#report.checks[2].detail <= Qualification.maximum_detail_bytes)
    local encoded = Qualification.encode(report)
    Assert.truthy(encoded:find("terminal_content", 1, true) ~= nil)
    Assert.equal(report.privacy.terminal_content, "excluded")
  end,
  compatibility_qualification_rejects_invalid_check_shapes = function()
    Assert.truthy(not pcall(Qualification.collect, {
      { name = "Neovim", status = "passed", detail = "bad name" },
    }, { doctor = doctor() }))
    Assert.truthy(not pcall(Qualification.collect, {
      { name = "neovim", status = "unknown", detail = "bad status" },
    }, { doctor = doctor() }))
  end,
}
