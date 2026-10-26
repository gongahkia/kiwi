local Coverage = {}

-- These scalars control shaping; they do not require independent ink. Keep
-- them in the HarfBuzz input, but not in Fontconfig's required character set.
function Coverage.ignorable(codepoint)
  return codepoint == 0x200c or codepoint == 0x200d
    or (codepoint >= 0xfe00 and codepoint <= 0xfe0f)
    or (codepoint >= 0xe0020 and codepoint <= 0xe007f)
    or (codepoint >= 0xe0100 and codepoint <= 0xe01ef)
end

return Coverage
