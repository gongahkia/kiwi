local Assert = require("tests.assert")
local Compatibility = require("kiwi.terminal.compatibility")

return {
  terminal_compatibility_manifest_is_versioned_bounded_and_detached = function()
    local manifest = Compatibility.snapshot()
    Assert.equal(manifest.schema_version, 1)
    Assert.equal(manifest.version, "1.4")
    Assert.equal(manifest.next_version, "1.5")
    Assert.truthy(#manifest.supported > 0 and #manifest.supported <= 32)
    Assert.truthy(#manifest.partial > 0 and #manifest.partial <= 32)
    Assert.truthy(#manifest.deferred > 0 and #manifest.deferred <= 32)
    Assert.truthy(#manifest.next > 0 and #manifest.next <= 32)
    manifest.supported[1] = "mutated"
    Assert.equal(Compatibility.snapshot().supported[1], "c0-controls")
  end,
  terminal_compatibility_manifest_keeps_unadvertised_features_explicit = function()
    local encoded = Compatibility.encode()
    Assert.truthy(encoded:find("terminfo%-256%-colour%-and%-direct%-rgb%-contract") ~= nil)
    Assert.truthy(encoded:find("kitty%-keyboard%-flag%-4%-macos%-and%-gtk") ~= nil)
    Assert.truthy(encoded:find("osc52%-read%-query%-host%-policy") ~= nil)
    Assert.truthy(encoded:find("xtshiftescape%-host%-selection%-policy") ~= nil)
    Assert.truthy(encoded:find("sixel%-video%-and%-broader%-kitty%-graphics") ~= nil)
    Assert.truthy(encoded:find("osc52%-read%-query%-clear%-and%-synchronization") == nil)
  end,
}
