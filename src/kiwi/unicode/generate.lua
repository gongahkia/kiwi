local input_directory = assert(arg[1], "usage: generate.lua <unicode-data-dir> <output.lua>")
local output_path = assert(arg[2], "usage: generate.lua <unicode-data-dir> <output.lua>")

local generator_version = "kiwi-unicode-generator-v1"
local source_files = {
  "EastAsianWidth.txt",
  "DerivedCoreProperties.txt",
  "emoji/emoji-data.txt",
  "emoji/emoji-variation-sequences.txt",
  "auxiliary/GraphemeBreakProperty.txt",
  "auxiliary/GraphemeBreakTest.txt",
}

local function read(path)
  local file, error_message = io.open(path, "rb")
  assert(file, "unable to read " .. path .. ": " .. tostring(error_message))
  local contents = file:read("*a")
  file:close()
  return contents
end

local function parse_codepoint(value)
  return assert(tonumber(value, 16), "invalid Unicode codepoint: " .. value)
end

local function parse_range(value)
  local first, last = value:match("^([0-9A-Fa-f]+)%.%.([0-9A-Fa-f]+)$")
  if first then
    return parse_codepoint(first), parse_codepoint(last)
  end
  local codepoint = parse_codepoint(value)
  return codepoint, codepoint
end

local function parse_property_file(path, wanted, transform)
  local ranges = {}
  for line in read(path):gmatch("[^\r\n]+") do
    local body = line:match("^%s*(.-)%s*#") or line
    local range, property = body:match("^%s*([0-9A-Fa-f.]+)%s*;%s*([^%s]+)")
    if range and wanted[property] then
      local first, last = parse_range(range)
      ranges[#ranges + 1] = { first, last, transform and transform(property) or property }
    end
  end
  table.sort(ranges, function(left, right)
    return left[1] == right[1] and left[2] < right[2] or left[1] < right[1]
  end)
  return ranges
end

local function write_flat_ranges(file, name, ranges, include_value)
  file:write("  ", name, " = {")
  for _, range in ipairs(ranges) do
    file:write(string.format("\n    0x%X, 0x%X", range[1], range[2]))
    if include_value then
      file:write(", ", tostring(range[3]))
    end
    file:write(",")
  end
  file:write("\n  },\n")
end

local incb_values = {
  Consonant = 1,
  Linker = 2,
  Extend = 3,
}

local function parse_indic_conjunct_break(path)
  local ranges = {}
  for line in read(path):gmatch("[^\r\n]+") do
    local body = line:match("^%s*(.-)%s*#") or line
    local range, property = body:match("^%s*([0-9A-Fa-f.]+)%s*;%s*InCB%s*;%s*([^%s]+)")
    if range and incb_values[property] then
      local first, last = parse_range(range)
      ranges[#ranges + 1] = { first, last, incb_values[property] }
    end
  end
  table.sort(ranges, function(left, right)
    return left[1] == right[1] and left[2] < right[2] or left[1] < right[1]
  end)
  return ranges
end

local function parse_emoji_variations(path)
  local text, emoji = {}, {}
  for line in read(path):gmatch("[^\r\n]+") do
    local body = line:match("^%s*(.-)%s*#") or line
    local base, selector, style = body:match("^%s*([0-9A-Fa-f]+)%s+([0-9A-Fa-f]+)%s*;%s*([^;]+)")
    if base and (selector == "FE0E" or selector == "FE0F") then
      local destination = style:match("text style") and text or style:match("emoji style") and emoji or nil
      if destination then
        local codepoint = parse_codepoint(base)
        destination[#destination + 1] = { codepoint, codepoint }
      end
    end
  end
  return text, emoji
end

local gcb_values = {
  CR = 1,
  LF = 2,
  Control = 3,
  Extend = 4,
  ZWJ = 5,
  Regional_Indicator = 6,
  Prepend = 7,
  SpacingMark = 8,
  L = 9,
  V = 10,
  T = 11,
  LV = 12,
  LVT = 13,
}

local data_path = function(relative_path)
  return input_directory .. "/" .. relative_path
end

local gcb = parse_property_file(data_path("auxiliary/GraphemeBreakProperty.txt"), gcb_values, function(property)
  return gcb_values[property]
end)
local east_asian_width = parse_property_file(data_path("EastAsianWidth.txt"), { F = true, W = true, A = true }, function(property)
  return ({ F = 1, W = 2, A = 3 })[property]
end)
local derived = parse_indic_conjunct_break(data_path("DerivedCoreProperties.txt"))
local emoji = parse_property_file(data_path("emoji/emoji-data.txt"), {
  Emoji = true,
  Emoji_Presentation = true,
  Emoji_Modifier = true,
  Emoji_Modifier_Base = true,
  Extended_Pictographic = true,
}, nil)

local emoji_by_property = {
  emoji = {},
  emoji_presentation = {},
  emoji_modifier = {},
  emoji_modifier_base = {},
  extended_pictographic = {},
}
for _, range in ipairs(emoji) do
  local destination = ({
    Emoji = emoji_by_property.emoji,
    Emoji_Presentation = emoji_by_property.emoji_presentation,
    Emoji_Modifier = emoji_by_property.emoji_modifier,
    Emoji_Modifier_Base = emoji_by_property.emoji_modifier_base,
    Extended_Pictographic = emoji_by_property.extended_pictographic,
  })[range[3]]
  destination[#destination + 1] = { range[1], range[2] }
end
local text_variation, emoji_variation = parse_emoji_variations(data_path("emoji/emoji-variation-sequences.txt"))

local output, error_message = io.open(output_path, "wb")
assert(output, "unable to write " .. output_path .. ": " .. tostring(error_message))
output:write("-- Generated by ", generator_version, "; do not edit.\n")
output:write("-- Unicode source: 17.0.0. Regenerate with ./script/fetch-unicode && ./script/generate-unicode.\n")
output:write("return {\n  version = \"17.0.0\",\n  generator = \"", generator_version, "\",\n")
write_flat_ranges(output, "grapheme_break", gcb, true)
write_flat_ranges(output, "east_asian_width", east_asian_width, true)
write_flat_ranges(output, "indic_conjunct_break", derived, true)
write_flat_ranges(output, "text_variation", text_variation, false)
write_flat_ranges(output, "emoji_variation", emoji_variation, false)
for _, name in ipairs({ "emoji", "emoji_presentation", "emoji_modifier", "emoji_modifier_base", "extended_pictographic" }) do
  write_flat_ranges(output, name, emoji_by_property[name], false)
end
output:write("  sources = {\n")
for _, source in ipairs(source_files) do
  output:write("    \"", source, "\",\n")
end
output:write("  },\n}\n")
output:close()
