local Compositor = {}
Compositor.__index = Compositor

local function assert_viewport(viewport, width, height)
  assert(type(viewport) == "table", "compositor viewport must be a table")
  for _, name in ipairs({ "x", "y", "width", "height" }) do
    assert(type(viewport[name]) == "number" and viewport[name] % 1 == 0 and viewport[name] >= 0, "compositor viewport " .. name .. " must be a non-negative integer")
  end
  assert(viewport.width >= 1 and viewport.height >= 1, "compositor viewport dimensions must be positive")
  assert(viewport.x + viewport.width <= width and viewport.y + viewport.height <= height, "compositor viewport must fit inside the surface")
end

function Compositor.viewport(layout, cell_width, cell_height)
  assert(type(layout) == "table", "compositor layout must be a table")
  for _, name in ipairs({ "x", "y", "width", "height" }) do
    assert(type(layout[name]) == "number" and layout[name] % 1 == 0 and layout[name] >= 0, "compositor layout " .. name .. " must be a non-negative integer")
  end
  assert(type(cell_width) == "number" and cell_width >= 1 and cell_width % 1 == 0, "compositor cell width must be a positive integer")
  assert(type(cell_height) == "number" and cell_height >= 1 and cell_height % 1 == 0, "compositor cell height must be a positive integer")
  assert(layout.width >= 1 and layout.height >= 1, "compositor pane dimensions must be positive")
  return {
    x = layout.x * cell_width,
    y = layout.y * cell_height,
    width = layout.width * cell_width,
    height = layout.height * cell_height,
  }
end

function Compositor.new(context)
  assert(type(context) == "table" and context.window, "compositor needs a presentation context")
  assert(type(context.begin_presentation_frame) == "function" and type(context.present_presentation_frame) == "function" and type(context.abort_presentation_frame) == "function", "compositor needs a presentation-frame lifecycle")
  return setmetatable({ context = context, frame = 0 }, Compositor)
end

function Compositor:validate(entries)
  assert(type(entries) == "table" and #entries > 0, "compositor needs at least one pane entry")
  assert(type(self.context.width) == "number" and type(self.context.height) == "number", "compositor context needs a configured surface")
  for index, entry in ipairs(entries) do
    assert(type(entry) == "table" and entry.renderer and entry.model, "compositor entry " .. index .. " needs a renderer and model")
    assert(type(entry.renderer.encode_into) == "function" and type(entry.renderer.finish_frame) == "function", "compositor entry renderer has no frame interface")
    assert_viewport(entry.viewport, self.context.width, self.context.height)
  end
end

function Compositor:can_present(entries)
  if self.context.window.minimized then return false end
  for _, entry in ipairs(entries) do
    if entry.model.modes and entry.model.modes.synchronized_output == true then return false end
  end
  return true
end

function Compositor:needs_render(entries, time)
  for _, entry in ipairs(entries) do
    if entry.renderer:needs_render(time) then return true end
  end
  return false
end

function Compositor:next_render_deadline(entries)
  local deadline
  for _, entry in ipairs(entries) do
    local candidate = entry.renderer:next_render_deadline()
    if candidate and (deadline == nil or candidate < deadline) then deadline = candidate end
  end
  return deadline
end

function Compositor:update_models(entries)
  for _, entry in ipairs(entries) do entry.renderer:update_model(entry.model) end
end

function Compositor:render(entries, time, debug_dirty, debug_boundaries)
  if self.context.window.minimized then return false, "zero-sized drawable" end
  self:validate(entries)
  local presentation, presentation_reason = self.context:begin_presentation_frame()
  if presentation == nil then return false, presentation_reason end
  local ok, result = xpcall(function()
    for index, entry in ipairs(entries) do
      entry.renderer:encode_into(presentation, entry.model, time, debug_dirty, debug_boundaries, {
        clear = index == 1,
        viewport = entry.viewport,
      })
    end
    self.frame = self.frame + 1
    if self.context.begin_framebuffer_capture then self.context:begin_framebuffer_capture(self.frame) end
    if self.context.encode_framebuffer_capture then self.context:encode_framebuffer_capture(presentation.encoder, presentation.texture) end
    if self.context.submit_framebuffer_capture then self.context:submit_framebuffer_capture() end
  end, debug.traceback)
  if not ok then
    self.context:abort_presentation_frame(presentation)
    error(result, 0)
  end
  local presented, present_reason = self.context:present_presentation_frame(presentation)
  if not presented then return false, present_reason end
  for _, entry in ipairs(entries) do entry.renderer:finish_frame(entry.model, time) end
  if self.context.poll_framebuffer_capture then self.context:poll_framebuffer_capture() end
  return true
end

return Compositor
