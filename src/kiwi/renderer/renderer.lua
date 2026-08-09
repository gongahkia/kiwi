local ffi = require("ffi")
local Packing = require("kiwi.renderer.packing")
local Passes = require("kiwi.renderer.passes")

ffi.cdef[[
typedef struct {
  float columns;
  float rows;
  float cursor_column;
  float cursor_row;
  float time;
  float show_dirty;
  float show_boundaries;
  float cursor_visible;
} KiwiFrameUniform;
]]

local Renderer = {}
Renderer.__index = Renderer

local function assert_handle(handle, label)
  if handle == nil then
    error(label .. " returned a null handle")
  end
  return handle
end

local function string_view(value)
  return ffi.new("WGPUStringView", { data = value, length = #value })
end

local function read_file(path)
  local file, error_message = io.open(path, "rb")
  if not file then
    error("Unable to load WGSL shader " .. path .. ": " .. error_message)
  end
  local contents = file:read("*a")
  file:close()
  return contents
end

local function color_to_u32(color)
  return ffi.cast("uint32_t", color)
end

local function select_glyph(atlas, glyph_text)
  local glyph = atlas:get(glyph_text)
  if glyph == nil and glyph_text ~= " " then
    return atlas:get("?"), "?"
  end
  return glyph, glyph_text
end

Renderer.select_glyph = select_glyph

function Renderer.new(context, font, model)
  Packing.assert_layout()
  local self = setmetatable({
    context = context,
    native = context.native,
    font = font,
    capacity = model.columns * model.rows,
    cells = ffi.new("KiwiGlyphInstance[?]", model.columns * model.rows),
    frame = ffi.new("KiwiFrameUniform[1]"),
    resources = {},
    diagnostics = {
      cells_uploaded = 0,
      bytes_uploaded = 0,
      dirty_cells = 0,
      dirty_ranges = 0,
      full_update = false,
      draw_calls = 0,
    },
  }, Renderer)
  local ok, result = xpcall(function()
    self:create_resources()
    model:mark_all_dirty()
    self:update_model(model)
  end, debug.traceback)
  if not ok then
    self:destroy()
    error(result)
  end
  return self
end

function Renderer:create_buffer(label, size, usage)
  local descriptor = ffi.new("WGPUBufferDescriptor")
  descriptor.label = string_view(label)
  descriptor.size = size
  descriptor.usage = usage
  local buffer = assert_handle(self.native.lib.wgpuDeviceCreateBuffer(self.context.device, descriptor), "buffer creation for " .. label)
  self.resources[#self.resources + 1] = { handle = buffer, release = self.native.lib.wgpuBufferRelease, destroy = self.native.lib.wgpuBufferDestroy }
  return buffer
end

function Renderer:create_resources()
  local api = self.native.lib
  local c = self.native.constants
  self.cell_buffer = self:create_buffer("terminal-cell-storage", self.capacity * Packing.glyph_instance_size, c.buffer_usage_storage + c.buffer_usage_copy_dst)
  self.frame_buffer = self:create_buffer("terminal-frame-uniform", ffi.sizeof("KiwiFrameUniform"), c.buffer_usage_uniform + c.buffer_usage_copy_dst)

  local texture_descriptor = ffi.new("WGPUTextureDescriptor")
  texture_descriptor.label = string_view("freetype-glyph-atlas")
  texture_descriptor.usage = c.texture_usage_copy_dst + c.texture_usage_texture_binding
  texture_descriptor.dimension = c.texture_dimension_2d
  texture_descriptor.size.width = self.font.atlas.width
  texture_descriptor.size.height = self.font.atlas.height
  texture_descriptor.size.depthOrArrayLayers = 1
  texture_descriptor.format = c.texture_format_r8_unorm
  texture_descriptor.mipLevelCount = 1
  texture_descriptor.sampleCount = 1
  self.atlas_texture = assert_handle(api.wgpuDeviceCreateTexture(self.context.device, texture_descriptor), "glyph atlas texture creation")
  self.resources[#self.resources + 1] = { handle = self.atlas_texture, release = api.wgpuTextureRelease, destroy = api.wgpuTextureDestroy }

  local texture_destination = ffi.new("WGPUTexelCopyTextureInfo")
  texture_destination.texture = self.atlas_texture
  texture_destination.aspect = c.texture_aspect_all
  local texture_layout = ffi.new("WGPUTexelCopyBufferLayout")
  texture_layout.bytesPerRow = self.font.atlas.width
  texture_layout.rowsPerImage = self.font.atlas.height
  local texture_extent = ffi.new("WGPUExtent3D")
  texture_extent.width = self.font.atlas.width
  texture_extent.height = self.font.atlas.height
  texture_extent.depthOrArrayLayers = 1
  api.wgpuQueueWriteTexture(self.context.queue, texture_destination, self.font.pixels, self.font.pixel_bytes, texture_layout, texture_extent)

  self.atlas_view = assert_handle(api.wgpuTextureCreateView(self.atlas_texture, nil), "glyph atlas view creation")
  self.resources[#self.resources + 1] = { handle = self.atlas_view, release = api.wgpuTextureViewRelease }
  local sampler_descriptor = ffi.new("WGPUSamplerDescriptor")
  sampler_descriptor.label = string_view("glyph-atlas-sampler")
  sampler_descriptor.addressModeU = c.sampler_address_clamp_to_edge
  sampler_descriptor.addressModeV = c.sampler_address_clamp_to_edge
  sampler_descriptor.addressModeW = c.sampler_address_clamp_to_edge
  sampler_descriptor.magFilter = c.filter_nearest
  sampler_descriptor.minFilter = c.filter_nearest
  sampler_descriptor.mipmapFilter = c.mipmap_filter_nearest
  sampler_descriptor.lodMaxClamp = 32
  sampler_descriptor.maxAnisotropy = 1
  self.sampler = assert_handle(api.wgpuDeviceCreateSampler(self.context.device, sampler_descriptor), "glyph atlas sampler creation")
  self.resources[#self.resources + 1] = { handle = self.sampler, release = api.wgpuSamplerRelease }

  local entries = ffi.new("WGPUBindGroupLayoutEntry[4]")
  entries[0].binding = 0
  entries[0].visibility = c.shader_stage_vertex
  entries[0].buffer.type = c.buffer_binding_readonly_storage
  entries[1].binding = 1
  entries[1].visibility = c.shader_stage_fragment
  entries[1].texture.sampleType = c.texture_sample_type_float
  entries[1].texture.viewDimension = c.texture_view_dimension_2d
  entries[2].binding = 2
  entries[2].visibility = c.shader_stage_fragment
  entries[2].sampler.type = c.sampler_binding_filtering
  entries[3].binding = 3
  entries[3].visibility = c.shader_stage_vertex + c.shader_stage_fragment
  entries[3].buffer.type = c.buffer_binding_uniform
  entries[3].buffer.minBindingSize = ffi.sizeof("KiwiFrameUniform")
  local layout_descriptor = ffi.new("WGPUBindGroupLayoutDescriptor")
  layout_descriptor.label = string_view("terminal-bindings")
  layout_descriptor.entryCount = 4
  layout_descriptor.entries = entries
  self.bind_group_layout = assert_handle(api.wgpuDeviceCreateBindGroupLayout(self.context.device, layout_descriptor), "terminal bind-group layout creation")
  self.resources[#self.resources + 1] = { handle = self.bind_group_layout, release = api.wgpuBindGroupLayoutRelease }

  local layouts = ffi.new("WGPUBindGroupLayout[1]", self.bind_group_layout)
  local pipeline_layout_descriptor = ffi.new("WGPUPipelineLayoutDescriptor")
  pipeline_layout_descriptor.label = string_view("terminal-pipeline-layout")
  pipeline_layout_descriptor.bindGroupLayoutCount = 1
  pipeline_layout_descriptor.bindGroupLayouts = layouts
  self.pipeline_layout = assert_handle(api.wgpuDeviceCreatePipelineLayout(self.context.device, pipeline_layout_descriptor), "terminal pipeline layout creation")
  self.resources[#self.resources + 1] = { handle = self.pipeline_layout, release = api.wgpuPipelineLayoutRelease }

  local bind_entries = ffi.new("WGPUBindGroupEntry[4]")
  bind_entries[0].binding = 0
  bind_entries[0].buffer = self.cell_buffer
  bind_entries[0].size = self.capacity * Packing.glyph_instance_size
  bind_entries[1].binding = 1
  bind_entries[1].textureView = self.atlas_view
  bind_entries[2].binding = 2
  bind_entries[2].sampler = self.sampler
  bind_entries[3].binding = 3
  bind_entries[3].buffer = self.frame_buffer
  bind_entries[3].size = ffi.sizeof("KiwiFrameUniform")
  local bind_group_descriptor = ffi.new("WGPUBindGroupDescriptor")
  bind_group_descriptor.label = string_view("terminal-bind-group")
  bind_group_descriptor.layout = self.bind_group_layout
  bind_group_descriptor.entryCount = 4
  bind_group_descriptor.entries = bind_entries
  self.bind_group = assert_handle(api.wgpuDeviceCreateBindGroup(self.context.device, bind_group_descriptor), "terminal bind-group creation")
  self.resources[#self.resources + 1] = { handle = self.bind_group, release = api.wgpuBindGroupRelease }

  local root = os.getenv("KIWI_ROOT") or "."
  self.shader_code = read_file(root .. "/src/kiwi/renderer/terminal.wgsl")
  self.shader = assert_handle(self.native.surface.kiwi_shader_from_wgsl(self.context.device, self.shader_code), "terminal WGSL module creation")
  self.resources[#self.resources + 1] = { handle = self.shader, release = api.wgpuShaderModuleRelease }

  self.background_pipeline = self:create_pipeline("background-pass", "background_vs", "background_fs")
  self.glyph_pipeline = self:create_pipeline("glyph-pass", "glyph_vs", "glyph_fs")
  self.cursor_pipeline = self:create_pipeline("cursor-pass", "cursor_vs", "cursor_fs")
  self.passes = Passes.build(self)
end

function Renderer:create_pipeline(label, vertex_entry, fragment_entry)
  local api = self.native.lib
  local c = self.native.constants
  local target = ffi.new("WGPUColorTargetState[1]")
  target[0].format = self.context.surface_format
  target[0].writeMask = c.color_write_all
  local fragment = ffi.new("WGPUFragmentState")
  fragment.module = self.shader
  fragment.entryPoint = string_view(fragment_entry)
  fragment.targetCount = 1
  fragment.targets = target
  local descriptor = ffi.new("WGPURenderPipelineDescriptor")
  descriptor.label = string_view(label)
  descriptor.layout = self.pipeline_layout
  descriptor.vertex.module = self.shader
  descriptor.vertex.entryPoint = string_view(vertex_entry)
  descriptor.primitive.topology = c.primitive_triangle_list
  descriptor.primitive.frontFace = c.front_face_ccw
  descriptor.primitive.cullMode = c.cull_none
  descriptor.multisample.count = 1
  descriptor.multisample.mask = 0xffffffff
  descriptor.fragment = fragment
  local pipeline = assert_handle(api.wgpuDeviceCreateRenderPipeline(self.context.device, descriptor), "render pipeline creation for " .. label)
  api.wgpuInstanceProcessEvents(self.context.instance)
  local native_error = ffi.string(self.native.surface.kiwi_surface_last_error())
  if #native_error > 0 then
    api.wgpuRenderPipelineRelease(pipeline)
    error("render pipeline creation for " .. label .. " failed: " .. native_error)
  end
  self.resources[#self.resources + 1] = { handle = pipeline, release = api.wgpuRenderPipelineRelease }
  return pipeline
end

function Renderer:pack_cell(model, index)
  local column, row = model:position(index)
  local cell = model.cells[index]
  local glyph, glyph_key = select_glyph(self.font.atlas, cell.glyph)
  local instance = self.cells[index]
  instance.x = column
  instance.y = row
  instance.fg = color_to_u32(cell.fg)
  instance.bg = color_to_u32(cell.bg)
  instance.flags = cell.flags
  if glyph and cell.glyph ~= " " then
    instance.u0 = glyph.u0
    instance.v0 = glyph.v0
    instance.u1 = glyph.u1
    instance.v1 = glyph.v1
    instance.glyph = string.byte(glyph_key)
  else
    instance.u0 = 0
    instance.v0 = 0
    instance.u1 = 0
    instance.v1 = 0
    instance.glyph = 0
  end
end

function Renderer:update_model(model)
  local damage = model.damage
  local ranges = damage:ranges()
  self.diagnostics.dirty_cells = damage.dirty_count
  self.diagnostics.dirty_ranges = #ranges
  self.diagnostics.full_update = damage.full
  self.diagnostics.cells_uploaded = 0
  self.diagnostics.bytes_uploaded = 0
  for _, range in ipairs(ranges) do
    for index = range.first, range.first + range.count - 1 do
      self:pack_cell(model, index)
    end
    local bytes = range.count * Packing.glyph_instance_size
    self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.cell_buffer, range.first * Packing.glyph_instance_size, self.cells + range.first, bytes)
    self.diagnostics.cells_uploaded = self.diagnostics.cells_uploaded + range.count
    self.diagnostics.bytes_uploaded = self.diagnostics.bytes_uploaded + bytes
  end
  damage:clear()
end

function Renderer:update_frame(model, time, debug_dirty, debug_boundaries)
  self.frame[0].columns = model.columns
  self.frame[0].rows = model.rows
  self.frame[0].cursor_column = model.cursor.column
  self.frame[0].cursor_row = model.cursor.row
  self.frame[0].time = time
  self.frame[0].show_dirty = debug_dirty and 1 or 0
  self.frame[0].show_boundaries = debug_boundaries and 1 or 0
  self.frame[0].cursor_visible = model.cursor.visible == false and 0 or 1
  self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.frame_buffer, 0, self.frame, ffi.sizeof("KiwiFrameUniform"))
end

function Renderer:encode_semantic_pass(pass_info, encoder, view, model)
  local attachment = ffi.new("WGPURenderPassColorAttachment")
  attachment.view = view
  attachment.depthSlice = 0xffffffff
  attachment.loadOp = pass_info.load_op
  attachment.storeOp = self.native.constants.store_store
  attachment.clearValue.r = 0.075
  attachment.clearValue.g = 0.09
  attachment.clearValue.b = 0.12
  attachment.clearValue.a = 1
  local descriptor = ffi.new("WGPURenderPassDescriptor")
  descriptor.label = string_view(pass_info.name)
  descriptor.colorAttachmentCount = 1
  descriptor.colorAttachments = attachment
  local pass = assert_handle(self.native.lib.wgpuCommandEncoderBeginRenderPass(encoder, descriptor), "render-pass creation for " .. pass_info.name)
  self.native.lib.wgpuRenderPassEncoderSetPipeline(pass, pass_info.pipeline)
  self.native.lib.wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nil)
  self.native.lib.wgpuRenderPassEncoderDraw(pass, 6, pass_info.instances(model), 0, 0)
  self.native.lib.wgpuRenderPassEncoderEnd(pass)
  self.native.lib.wgpuRenderPassEncoderRelease(pass)
end

function Renderer:render(model, time, debug_dirty, debug_boundaries)
  if self.context.window.minimized then
    return false, "zero-sized drawable"
  end
  if self.context.window.resized and not self.context:configure_surface() then
    return false, "zero-sized drawable"
  end
  self:update_frame(model, time, debug_dirty, debug_boundaries)
  local surface_texture = ffi.new("WGPUSurfaceTexture")
  self.native.lib.wgpuSurfaceGetCurrentTexture(self.context.surface, surface_texture)
  local c = self.native.constants
  if surface_texture.status ~= c.surface_success_optimal and surface_texture.status ~= c.surface_success_suboptimal then
    return false, "surface acquire status " .. tonumber(surface_texture.status)
  end
  local view = assert_handle(self.native.lib.wgpuTextureCreateView(surface_texture.texture, nil), "surface texture view creation")
  local encoder = assert_handle(self.native.lib.wgpuDeviceCreateCommandEncoder(self.context.device, nil), "command encoder creation")
  for _, pass_info in ipairs(self.passes) do
    pass_info:encode(self, encoder, view, model)
  end
  local commands = ffi.new("WGPUCommandBuffer[1]")
  commands[0] = assert_handle(self.native.lib.wgpuCommandEncoderFinish(encoder, nil), "command-buffer creation")
  self.native.lib.wgpuQueueSubmit(self.context.queue, 1, commands)
  self.native.lib.wgpuCommandBufferRelease(commands[0])
  self.native.lib.wgpuCommandEncoderRelease(encoder)
  self.native.lib.wgpuTextureViewRelease(view)
  local present_status = self.native.lib.wgpuSurfacePresent(self.context.surface)
  self.native.lib.wgpuTextureRelease(surface_texture.texture)
  if surface_texture.status == c.surface_success_suboptimal then
    self.context.window.resized = true
  end
  if present_status ~= 1 then
    return false, "surface present status " .. tonumber(present_status)
  end
  self.native.lib.wgpuInstanceProcessEvents(self.context.instance)
  local native_error = ffi.string(self.native.surface.kiwi_surface_last_error())
  if #native_error > 0 then
    return false, "native GPU error: " .. native_error
  end
  self.diagnostics.draw_calls = 3
  return true
end

function Renderer:destroy()
  for index = #self.resources, 1, -1 do
    local resource = self.resources[index]
    if resource.destroy then
      resource.destroy(resource.handle)
    end
    resource.release(resource.handle)
  end
  self.resources = {}
end

return Renderer
