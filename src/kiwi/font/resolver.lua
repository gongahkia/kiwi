local ffi = require("ffi")
local native = require("kiwi.ffi.fontconfig")

local Resolver = {}
Resolver.__index = Resolver

local function require_success(value, operation)
  if value == 0 then error("Fontconfig " .. operation .. " failed") end
end

local function match_pattern(family, codepoints, monospace, style)
  local api, object = native.lib, native.object
  local pattern = api.FcPatternCreate()
  if pattern == nil then error("Fontconfig pattern creation returned a null handle") end
  local charset
  local ok, result = xpcall(function()
    if family then require_success(api.FcPatternAddString(pattern, object.family, family), "family pattern construction") end
    if monospace then require_success(api.FcPatternAddInteger(pattern, object.spacing, native.mono_spacing), "spacing pattern construction") end
    require_success(api.FcPatternAddInteger(pattern, object.weight, style and style.bold and native.weight_bold or native.weight_regular), "weight pattern construction")
    require_success(api.FcPatternAddInteger(pattern, object.slant, style and style.italic and native.slant_italic or native.slant_roman), "slant pattern construction")
    if codepoints and #codepoints > 0 then
      charset = api.FcCharSetCreate()
      if charset == nil then error("Fontconfig charset creation returned a null handle") end
      for _, codepoint in ipairs(codepoints) do
        require_success(api.FcCharSetAddChar(charset, codepoint), "charset construction")
      end
      require_success(api.FcPatternAddCharSet(pattern, object.charset, charset), "charset pattern construction")
    end
    require_success(api.FcConfigSubstitute(nil, pattern, native.match_pattern), "pattern substitution")
    api.FcDefaultSubstitute(pattern)
    local match_result = ffi.new("int[1]")
    local match = api.FcFontMatch(nil, pattern, match_result)
    if match == nil or match_result[0] ~= native.result_match then return nil end
    local path_out = ffi.new("FcChar8*[1]")
    if api.FcPatternGetString(match, object.file, 0, path_out) ~= native.result_match then
      api.FcPatternDestroy(match)
      return nil
    end
    local index_out = ffi.new("int[1]")
    local index = api.FcPatternGetInteger(match, object.index, 0, index_out) == native.result_match and tonumber(index_out[0]) or 0
    local result = { path = ffi.string(path_out[0]), index = index }
    api.FcPatternDestroy(match)
    return result
  end, debug.traceback)
  if charset ~= nil then api.FcCharSetDestroy(charset) end
  api.FcPatternDestroy(pattern)
  if not ok then error(result) end
  return result
end

function Resolver.new(options)
  options = options or {}
  require_success(native.lib.FcInit(), "initialization")
  return setmetatable({ primary_family = options.primary_family or "monospace" }, Resolver)
end

function Resolver:primary(style, family)
  return assert(match_pattern(family or self.primary_family, nil, true, style), "Fontconfig found no monospace primary font for " .. self.primary_family)
end

function Resolver:fallback(codepoints, style)
  return match_pattern(nil, codepoints, false, style)
end

return Resolver
