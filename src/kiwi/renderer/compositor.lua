local ffi = require("ffi")

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
  assert(type(context) == "table" and context.native and context.window, "compositor needs a GPU context")
  return setmetatable({ context = context, native = context.native, frame = 0 }, Compositor)
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
  if self.context.window.resized and not self.context:configure_surface() then return false, "zero-sized drawable" end
  self:validate(entries)
  local api = self.native.lib
  local c = self.native.constants
  local surface_texture = ffi.new("WGPUSurfaceTexture")
  api.wgpuSurfaceGetCurrentTexture(self.context.surface, surface_texture)
  if surface_texture.status == c.surface_occluded then return false, "surface occluded" end
  if surface_texture.status ~= c.surface_success_optimal and surface_texture.status ~= c.surface_success_suboptimal then
    return false, "surface acquire status " .. tonumber(surface_texture.status)
  end
  local view = api.wgpuTextureCreateView(surface_texture.texture, nil)
  if view == nil then
    api.wgpuTextureRelease(surface_texture.texture)
    error("surface texture view creation returned a null handle")
  end
  local encoder = api.wgpuDeviceCreateCommandEncoder(self.context.device, nil)
  if encoder == nil then
    api.wgpuTextureViewRelease(view)
    api.wgpuTextureRelease(surface_texture.texture)
    error("command encoder creation returned a null handle")
  end
  local ok, result = xpcall(function()
    for index, entry in ipairs(entries) do
      entry.renderer:encode_into(encoder, view, entry.model, time, debug_dirty, debug_boundaries, {
        clear = index == 1,
        viewport = entry.viewport,
      })
    end
    self.frame = self.frame + 1
    self.context:begin_framebuffer_capture(self.frame)
    self.context:encode_framebuffer_capture(encoder, surface_texture.texture)
    local commands = ffi.new("WGPUCommandBuffer[1]")
    commands[0] = api.wgpuCommandEncoderFinish(encoder, nil)
    if commands[0] == nil then error("command-buffer creation returned a null handle") end
    api.wgpuQueueSubmit(self.context.queue, 1, commands)
    api.wgpuCommandBufferRelease(commands[0])
    self.context:submit_framebuffer_capture()
  end, debug.traceback)
  api.wgpuCommandEncoderRelease(encoder)
  api.wgpuTextureViewRelease(view)
  local present_status
  if ok then present_status = api.wgpuSurfacePresent(self.context.surface) end
  api.wgpuTextureRelease(surface_texture.texture)
  if not ok then error(result, 0) end
  if surface_texture.status == c.surface_success_suboptimal then self.context.window.resized = true end
  if present_status ~= 1 then return false, "surface present status " .. tonumber(present_status) end
  local native_error = ffi.string(self.native.surface.kiwi_surface_last_error())
  if #native_error > 0 then return false, "native GPU error: " .. native_error end
  for _, entry in ipairs(entries) do entry.renderer:finish_frame(entry.model, time) end
  self.context:poll_framebuffer_capture()
  return true
end

return Compositor
