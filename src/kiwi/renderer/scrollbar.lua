-- Renderer-neutral primary-screen scrollback viewport geometry.
--
-- This is presentation state, not terminal protocol state: the terminal only
-- exposes its bounded history and current viewport offset. Native hosts may
-- render this descriptor as an overlay and route pointer events back through
-- its companion input module.
local Color = require("kiwi.renderer.color")

local Scrollbar = {}

Scrollbar.default_policy = "always"
Scrollbar.minimum_thumb_rows = 2
Scrollbar.track_inset_columns = 0.25
Scrollbar.track_width_columns = 0.55

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

local function finite_integer(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
    and value >= 0 and value % 1 == 0
end

local function color_descriptor(model)
  local color = Scrollbar.default_color
  if type(model) == "table" then
    if type(model.presentation_colors) == "function" and type(model.default_cell) == "table" then
      color = select(1, model:presentation_colors(model.default_cell)) or color
    elseif type(model.colors) == "table" and type(model.colors.foreground) == "number" then
      color = model.colors.foreground
    end
  end
  local channels = Color.unpack(color)
  return {
    alpha = 0.58,
    blue = channels.blue / 255,
    green = channels.green / 255,
    red = channels.red / 255,
  }
end

function Scrollbar.validate_policy(policy)
  policy = policy or Scrollbar.default_policy
  assert(policy == "always" or policy == "never", "scrollbar policy must be always or never")
  return policy
end

local function inactive(model)
  return {
    active = false,
    bottom = 0,
    color = color_descriptor(model),
    history_offset = 0,
    history_size = 0,
    left = 0,
    right = 0,
    thumb_size = 0,
    top = 0,
    viewport_rows = 0,
  }
end

function Scrollbar.descriptor(model, policy)
  policy = Scrollbar.validate_policy(policy)
  local descriptor = inactive(model)
  if policy == "never" or type(model) ~= "table" or model.active_screen ~= model.primary
    or type(model.scrollback) ~= "table" or type(model.scrollback.size) ~= "function"
    or not finite_integer(model.columns) or model.columns < 1 or not finite_integer(model.rows) or model.rows < 1 then
    return descriptor
  end
  local history_size = model.scrollback:size()
  local history_offset = model.history_offset
  if not finite_integer(history_size) or not finite_integer(history_offset) or history_size < 1 then return descriptor end
  history_offset = clamp(history_offset, 0, history_size)
  local natural_thumb_size = model.rows / (history_size + model.rows)
  local thumb_size = math.max(natural_thumb_size, math.min(1, Scrollbar.minimum_thumb_rows / model.rows))
  local travel = 1 - thumb_size
  local progress = history_size == 0 and 1 or (history_size - history_offset) / history_size
  descriptor.active = thumb_size < 1
  descriptor.bottom = travel * progress + thumb_size
  descriptor.history_offset = history_offset
  descriptor.history_size = history_size
  descriptor.left = math.max(0, model.columns - Scrollbar.track_inset_columns - Scrollbar.track_width_columns)
  descriptor.right = math.max(descriptor.left, model.columns - Scrollbar.track_inset_columns)
  descriptor.thumb_size = thumb_size
  descriptor.top = travel * progress
  descriptor.viewport_rows = model.rows
  return descriptor
end

function Scrollbar.same(left, right)
  if left == right then return true end
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  for _, name in ipairs({ "active", "bottom", "history_offset", "history_size", "left", "right", "thumb_size", "top", "viewport_rows" }) do
    if left[name] ~= right[name] then return false end
  end
  local first, second = left.color, right.color
  return type(first) == "table" and type(second) == "table"
    and first.red == second.red and first.green == second.green and first.blue == second.blue and first.alpha == second.alpha
end

Scrollbar.default_color = Color.pack(0xd8, 0xde, 0xe9, 0xff)

return Scrollbar
