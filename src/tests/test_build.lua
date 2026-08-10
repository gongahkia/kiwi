local Assert = require("tests.assert")
local Build = require("kiwi.build")

return {
  build_metadata_uses_one_version_source_and_marks_release_mode = function()
    local values = {
      ["/fixture/VERSION"] = "0.1.0",
      ["/fixture/BUILD_REVISION"] = "0123456789abcdef",
    }
    local release = Build.info({
      root = "/fixture",
      getenv = function(name) return name == "KIWI_RELEASE" and "1" or nil end,
      read = function(path) return values[path] end,
    })
    Assert.equal(release.version, "0.1.0")
    Assert.equal(release.revision, "0123456789abcdef")
    Assert.equal(release.release_mode, true)
    Assert.equal(Build.format(release), "Kiwi 0.1.0 (revision 0123456789abcdef, mode release)")
  end,
  build_metadata_falls_back_to_source_revision_for_a_checkout = function()
    local info = Build.info({
      root = "/fixture",
      getenv = function() return nil end,
      read = function(path) return path:match("VERSION$") and "0.1.0" or nil end,
    })
    Assert.equal(info.revision, "source")
    Assert.equal(info.release_mode, false)
  end,
}
