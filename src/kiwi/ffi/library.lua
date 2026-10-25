local ffi = require("ffi")
local Library = {}

-- Respect the platform loader first (including packaged Linux library paths).
-- Homebrew opt links also work when a formula is installed but not globally
-- linked, and do not depend on DYLD variables surviving a macOS app launch.
function Library.load(names, formula, options)
  options = options or {}
  if type(names) == "string" then names = { names } end
  local load = options.load or ffi.load
  local candidates = {}
  for _, name in ipairs(names) do candidates[#candidates + 1] = name end
  if (options.platform or ffi.os) == "OSX" then
    local prefixes = (options.architecture or ffi.arch) == "arm64"
      and { "/opt/homebrew", "/usr/local" } or { "/usr/local", "/opt/homebrew" }
    for _, prefix in ipairs(prefixes) do
      for _, name in ipairs(names) do
        if name:match("^[%w_]+$") then
          candidates[#candidates + 1] = prefix .. "/opt/" .. formula .. "/lib/lib" .. name .. ".dylib"
        end
      end
    end
  end
  local failure
  for _, candidate in ipairs(candidates) do
    local ok, library = pcall(load, candidate)
    if ok then return library end
    failure = library
  end
  error("cannot load " .. table.concat(names, "/") .. " (tried " .. table.concat(candidates, ", ") .. "): " .. tostring(failure))
end

return Library
