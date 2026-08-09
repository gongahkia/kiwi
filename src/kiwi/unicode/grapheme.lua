local Properties = require("kiwi.unicode.properties")

local Grapheme = {}

local GCB = Properties.grapheme_break
local InCB = Properties.indic_conjunct_break

local function ends_with_incb_linker_sequence(codepoints, current)
  if Properties.incb(current) ~= InCB.consonant then
    return false
  end
  local saw_linker = false
  for index = #codepoints, 1, -1 do
    local property = Properties.incb(codepoints[index])
    if property == InCB.extend then
      -- continue
    elseif property == InCB.linker then
      saw_linker = true
    else
      return saw_linker and property == InCB.consonant
    end
  end
  return false
end

local function ends_with_extended_pictographic_zwj(codepoints, current)
  if not Properties.has("extended_pictographic", current) then
    return false
  end
  local index = #codepoints
  if index == 0 or Properties.gcb(codepoints[index]) ~= GCB.zwj then
    return false
  end
  index = index - 1
  while index > 0 and Properties.gcb(codepoints[index]) == GCB.extend do
    index = index - 1
  end
  return index > 0 and Properties.has("extended_pictographic", codepoints[index])
end

local function has_odd_trailing_regional_indicators(codepoints)
  local count = 0
  for index = #codepoints, 1, -1 do
    if Properties.gcb(codepoints[index]) ~= GCB.regional_indicator then
      break
    end
    count = count + 1
  end
  return count % 2 == 1
end

function Grapheme.should_break(codepoints, current)
  if #codepoints == 0 then
    return true
  end
  local previous = codepoints[#codepoints]
  local left, right = Properties.gcb(previous), Properties.gcb(current)

  if left == GCB.cr and right == GCB.lf then return false end
  if left == GCB.cr or left == GCB.lf or left == GCB.control then return true end
  if right == GCB.cr or right == GCB.lf or right == GCB.control then return true end
  if left == GCB.l and (right == GCB.l or right == GCB.v or right == GCB.lv or right == GCB.lvt) then return false end
  if (left == GCB.lv or left == GCB.v) and (right == GCB.v or right == GCB.t) then return false end
  if (left == GCB.lvt or left == GCB.t) and right == GCB.t then return false end
  if right == GCB.extend or right == GCB.zwj then return false end
  if right == GCB.spacing_mark then return false end
  if left == GCB.prepend then return false end
  if ends_with_incb_linker_sequence(codepoints, current) then return false end
  if ends_with_extended_pictographic_zwj(codepoints, current) then return false end
  if left == GCB.regional_indicator and right == GCB.regional_indicator and has_odd_trailing_regional_indicators(codepoints) then return false end
  return true
end

function Grapheme.boundaries(codepoints)
  local boundaries = { true }
  local cluster = {}
  for index, codepoint in ipairs(codepoints) do
    local boundary = Grapheme.should_break(cluster, codepoint)
    boundaries[index] = boundary
    if boundary then
      cluster = { codepoint }
    else
      cluster[#cluster + 1] = codepoint
    end
  end
  boundaries[#codepoints + 1] = true
  return boundaries
end

function Grapheme.segment(codepoints)
  local clusters = {}
  local cluster
  for _, codepoint in ipairs(codepoints) do
    if cluster == nil or Grapheme.should_break(cluster, codepoint) then
      cluster = { codepoint }
      clusters[#clusters + 1] = cluster
    else
      cluster[#cluster + 1] = codepoint
    end
  end
  return clusters
end

return Grapheme
