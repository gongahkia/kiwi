local Generated = require("kiwi.unicode.generated")

local Properties = {
  version = Generated.version,
  grapheme_break = {
    other = 0,
    cr = 1,
    lf = 2,
    control = 3,
    extend = 4,
    zwj = 5,
    regional_indicator = 6,
    prepend = 7,
    spacing_mark = 8,
    l = 9,
    v = 10,
    t = 11,
    lv = 12,
    lvt = 13,
  },
  indic_conjunct_break = {
    none = 0,
    consonant = 1,
    linker = 2,
    extend = 3,
  },
  east_asian_width = {
    neutral = 0,
    fullwidth = 1,
    wide = 2,
    ambiguous = 3,
  },
}

local function value_for(flat_ranges, stride, codepoint, default)
  local first, last = 1, #flat_ranges / stride
  while first <= last do
    local middle = math.floor((first + last) / 2)
    local offset = (middle - 1) * stride + 1
    local lower, upper = flat_ranges[offset], flat_ranges[offset + 1]
    if codepoint < lower then
      last = middle - 1
    elseif codepoint > upper then
      first = middle + 1
    else
      return flat_ranges[offset + 2] or true
    end
  end
  return default
end

function Properties.gcb(codepoint)
  return value_for(Generated.grapheme_break, 3, codepoint, Properties.grapheme_break.other)
end

function Properties.incb(codepoint)
  return value_for(Generated.indic_conjunct_break, 3, codepoint, Properties.indic_conjunct_break.none)
end

function Properties.east_asian_width_of(codepoint)
  return value_for(Generated.east_asian_width, 3, codepoint, Properties.east_asian_width.neutral)
end

function Properties.has(name, codepoint)
  local ranges = assert(Generated[name], "unknown Unicode property: " .. tostring(name))
  return value_for(ranges, 2, codepoint, false)
end

function Properties.is_private_use(codepoint)
  return (codepoint >= 0xe000 and codepoint <= 0xf8ff)
    or (codepoint >= 0xf0000 and codepoint <= 0xffffd)
    or (codepoint >= 0x100000 and codepoint <= 0x10fffd)
end

function Properties.is_control(codepoint)
  local gcb = Properties.gcb(codepoint)
  return gcb == Properties.grapheme_break.cr or gcb == Properties.grapheme_break.lf or gcb == Properties.grapheme_break.control
end

return Properties
