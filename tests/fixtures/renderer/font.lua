local Font = {}

function Font.new(options)
  options = options or {}
  local unsupported = options.unsupported or {}
  return {
    getAscent = function()
      return 12.8
    end,
    getHeight = function()
      return 16.2
    end,
    getWidth = function(_, text)
      if text == "M" then
        return 8.2
      end
      if text == "A" then
        return 7
      end
      if text == "é" then
        return 9
      end
      return #text
    end,
    hasGlyphs = function(_, text)
      return unsupported[text] ~= true
    end,
  }
end

return Font
