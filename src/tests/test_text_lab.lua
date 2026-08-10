local Assert = require("tests.assert")
local LabConfig = require("kiwi.text.lab")
local TextLab = require("kiwi.bench.text_lab")

return {
  text_laboratory_gates_backend_selection_and_validates_the_bounded_list = function()
    Assert.equal(LabConfig.requested_backend(function() return nil end), "atlas")
    Assert.equal(LabConfig.requested_backend(function(name)
      return name == "KIWI_TEXT_BACKEND" and "msdf" or nil
    end), "atlas")
    Assert.equal(LabConfig.requested_backend(function(name)
      return name == "KIWI_TEXT_LAB" and "1" or name == "KIWI_TEXT_LAB_BACKEND" and "msdf" or nil
    end), "msdf")
    local names = LabConfig.parse_backends("atlas,msdf")
    Assert.equal(#names, 2)
    Assert.equal(names[2], "msdf")
    local invalid = pcall(function() LabConfig.parse_backends("atlas,,msdf") end)
    Assert.equal(invalid, false)
  end,
  text_laboratory_records_baseline_fallbacks_as_unavailable = function()
    local report = TextLab.report({
      timestamp = "20260810T000000Z",
      iterations = 1,
      warmup = 0,
      backends = { "msdf" },
      corpus = { version = "kiwi-text-corpus-v1", scenarios = {} },
      metadata = { timestamp_utc = "20260810T000000Z" },
      font = { primary_path = "fixture" },
      describe = function(name)
        return {
          abi_version = 1,
          requested = name,
          active = name == "atlas" and "atlas" or "atlas",
          fallback = name ~= "atlas",
          fallback_reason = name ~= "atlas" and "unsupported-backend" or nil,
        }
      end,
      measure = function(name)
        return { { id = "fixture", requested = name } }
      end,
    })
    Assert.equal(#report.backends, 2)
    Assert.equal(report.backends[1].availability, "available")
    Assert.equal(report.backends[2].availability, "unavailable")
    Assert.equal(report.report.recommendation.status, "prototype-unavailable")
    Assert.equal(report.report.unavailable_environments[1].fallback_reason, "unsupported-backend")
  end,
}
