local Properties = require("kiwi.unicode.properties")

local Width = {
  policy_version = "kiwi-m2-width-v1",
  default_policy = {
    ambiguous_width = 1,
    private_use_width = 1,
  },
}

local EAW = Properties.east_asian_width

local function policy_value(policy, name)
  local value = policy[name] or Width.default_policy[name]
  assert(value == 1 or value == 2, name .. " must be 1 or 2")
  return value
end

function Width.normalize_policy(policy)
  policy = policy or Width.default_policy
  return {
    ambiguous_width = policy_value(policy, "ambiguous_width"),
    private_use_width = policy_value(policy, "private_use_width"),
  }
end

local function has_codepoint(codepoints, value)
  for _, codepoint in ipairs(codepoints) do
    if codepoint == value then return true end
  end
  return false
end

local function emoji_width(codepoints)
  local has_emoji = false
  local has_emoji_presentation = false
  local has_regional_indicator = false
  local has_extended_pictographic = false
  for _, codepoint in ipairs(codepoints) do
    has_emoji = has_emoji or Properties.has("emoji", codepoint)
    has_emoji_presentation = has_emoji_presentation or Properties.has("emoji_presentation", codepoint)
    has_regional_indicator = has_regional_indicator or Properties.gcb(codepoint) == Properties.grapheme_break.regional_indicator
    has_extended_pictographic = has_extended_pictographic or Properties.has("extended_pictographic", codepoint)
  end
  if has_codepoint(codepoints, 0xfe0e) then return nil end
  if has_codepoint(codepoints, 0x20e3) then return 2 end
  if has_regional_indicator then return 2 end
  if has_codepoint(codepoints, 0xfe0f) and has_emoji then return 2 end
  if has_emoji_presentation then return 2 end
  if has_extended_pictographic and has_emoji and has_codepoint(codepoints, 0x200d) then return 2 end
  return nil
end

function Width.columns(codepoints, policy)
  assert(type(codepoints) == "table" and #codepoints > 0, "terminal width needs a non-empty cluster")
  policy = policy or Width.default_policy
  local ambiguous_width = policy_value(policy, "ambiguous_width")
  local private_use_width = policy_value(policy, "private_use_width")
  local emoji = emoji_width(codepoints)
  if emoji then return emoji end
  for _, codepoint in ipairs(codepoints) do
    if Properties.is_private_use(codepoint) then
      return private_use_width
    end
    local east_asian_width = Properties.east_asian_width_of(codepoint)
    if east_asian_width == EAW.fullwidth or east_asian_width == EAW.wide then return 2 end
    if east_asian_width == EAW.ambiguous then
      return ambiguous_width
    end
  end
  return 1
end

return Width
