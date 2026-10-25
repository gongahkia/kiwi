local Assert = require("tests.assert")
local Library = require("kiwi.ffi.library")

return {
  library_loading_respects_the_platform_loader_before_homebrew_fallbacks = function()
    local seen = {}
    local lib = Library.load("freetype", "freetype", { platform = "OSX", architecture = "x64", load = function(path)
      seen[#seen + 1] = path
      if path == "/usr/local/opt/freetype/lib/libfreetype.dylib" then return "loaded" end
      error("unavailable")
    end })
    Assert.equal(lib, "loaded")
    Assert.equal(table.concat(seen, ","), "freetype,/usr/local/opt/freetype/lib/libfreetype.dylib")
    lib = Library.load("harfbuzz", "harfbuzz", { platform = "OSX", load = function(path)
      Assert.equal(path, "harfbuzz"); return "platform-library"
    end })
    Assert.equal(lib, "platform-library")
  end,
  library_loading_tries_architecture_appropriate_paths_and_keeps_linux_sonames = function()
    local seen = {}
    Library.load("gif", "giflib", { platform = "OSX", architecture = "arm64", load = function(path)
      seen[#seen + 1] = path
      if #seen == 2 then return {} end
      error("unavailable")
    end })
    Assert.equal(seen[2], "/opt/homebrew/opt/giflib/lib/libgif.dylib")
    seen = {}
    Library.load({ "gif", "libgif.so.7" }, "giflib", { platform = "Linux", load = function(path)
      seen[#seen + 1] = path
      if path == "libgif.so.7" then return {} end
      error("unavailable")
    end })
    Assert.equal(#seen, 2)
    local ok, reason = pcall(Library.load, "missing", "missing", { platform = "Linux", load = function() error("absent") end })
    Assert.equal(ok, false)
    Assert.truthy(reason:find("cannot load missing", 1, true))
  end,
}
