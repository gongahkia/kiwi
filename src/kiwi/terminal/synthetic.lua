local bit = require("bit")
local Terminal = require("kiwi.terminal.model")

local Synthetic = {}

local palette = {
  0xffd8dee9,
  0xff88c0d0,
  0xff81a1c1,
  0xffa3be8c,
  0xffebcb8b,
  0xffbf616a,
  0xffb48ead,
}

local backgrounds = { 0xff20242b, 0xff252a34, 0xff2d3440, 0xff333b48 }

local function next_random(state)
  state = bit.bxor(state, bit.lshift(state, 13))
  state = bit.bxor(state, bit.rshift(state, 17))
  state = bit.bxor(state, bit.lshift(state, 5))
  return bit.tobit(state)
end

local function positive(value)
  return value < 0 and -value or value
end

local function style(fg, bg, flags)
  return { fg = fg, bg = bg, flags = flags or 0 }
end

local function line(model, row, text, text_style)
  if row < model.rows then
    model:write(0, row, text, text_style)
  end
end

function Synthetic.new(seed, columns, rows)
  columns = columns or 160
  rows = rows or 50
  seed = seed or 0x4b495749
  local model = Terminal.new(columns, rows)
  local header = style(palette[2], backgrounds[2], Terminal.flags.bold)
  local prompt = style(palette[4], backgrounds[1], 0)
  local detail = style(palette[1], backgrounds[1], 0)
  local warning = style(palette[5], backgrounds[3], Terminal.flags.semantic)

  line(model, 0, " kiwi renderer laboratory  |  structured cells -> semantic GPU passes  |  seed " .. seed, header)
  line(model, 2, "dev@kiwi:~/lab$ ./measure --scenario typing --grid " .. columns .. "x" .. rows, prompt)
  line(model, 3, "[renderer] atlas=DejaVuSansMono  glyphs=95  upload=damage-ranges  backend=Vulkan", detail)
  line(model, 5, "  PID  CPU%   RSS     COMMAND", style(palette[3], backgrounds[2], Terminal.flags.bold))
  line(model, 6, "  812  0.3    42 MiB  kiwi --renderer-lab", detail)
  line(model, 7, "  917  0.1    17 MiB  shader-watch glyph.wgsl", detail)
  line(model, 9, "status: ready   cursor: animated   semantic cells: highlighted", style(palette[4], backgrounds[2], 0))
  line(model, 11, "warning: this is a renderer laboratory, not a VT parser yet.", warning)
  line(model, 13, "$ for i in {1..8}; do printf '%04d  glyph-cache-hit=%.2f%%\\n' $i 99.1; done", prompt)

  local random = seed
  for row = 16, rows - 2 do
    local chars = {}
    for column = 1, columns do
      random = next_random(random)
      local value = positive(random)
      if column % 29 == 0 then
        chars[#chars + 1] = "|"
      elseif column % 17 == 0 then
        chars[#chars + 1] = string.char(48 + value % 10)
      else
        chars[#chars + 1] = string.char(33 + value % 58)
      end
    end
    local fg = palette[(row % #palette) + 1]
    local bg = backgrounds[(row % #backgrounds) + 1]
    line(model, row, table.concat(chars), style(fg, bg, row % 7 == 0 and Terminal.flags.bold or 0))
  end

  if rows > 15 then
    line(model, rows - 1, "[F2] dirty cells  [F3] cell boundaries  [Esc] close", style(palette[7], backgrounds[2], 0))
  end
  model:set_cursor(math.min(27, columns - 1), math.min(2, rows - 1))
  model:clear_damage()
  return model
end

function Synthetic.apply(model, scenario, tick)
  tick = tick or 0
  if scenario == "static" then
    return 0
  end

  if scenario == "typing" then
    local count = tick % 4 + 1
    local row = math.min(2, model.rows - 1)
    local first = (tick * 3) % math.max(1, model.columns - count)
    for offset = 0, count - 1 do
      model:set(first + offset, row, {
        glyph = string.char(65 + (tick + offset) % 26),
        fg = palette[(tick + offset) % #palette + 1],
        bg = backgrounds[1],
        flags = Terminal.flags.recent,
      })
    end
    model:set_cursor(first + count - 1, row)
    return count
  end

  if scenario == "line-churn" then
    local row = 16 + tick % math.max(1, model.rows - 17)
    local characters = {}
    for column = 0, model.columns - 1 do
      characters[#characters + 1] = string.char(33 + (column + tick) % 58)
    end
    return model:write(0, row, table.concat(characters), style(palette[tick % #palette + 1], backgrounds[tick % #backgrounds + 1], Terminal.flags.recent))
  end

  if scenario == "scrolling" then
    local changed = 0
    for row = 16, model.rows - 2 do
      local characters = {}
      for column = 0, model.columns - 1 do
        characters[#characters + 1] = string.char(33 + (column + row + tick) % 58)
      end
      changed = changed + model:write(0, row, table.concat(characters), style(palette[row % #palette + 1], backgrounds[(row + tick) % #backgrounds + 1], 0))
    end
    return changed
  end

  if scenario == "full-redraw" then
    model:mark_all_dirty()
    return model.columns * model.rows
  end

  error("unknown synthetic scenario: " .. tostring(scenario))
end

function Synthetic.scenarios()
  return { "static", "typing", "line-churn", "scrolling", "full-redraw" }
end

return Synthetic
