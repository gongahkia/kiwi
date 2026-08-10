local ffi = require("ffi")
local Packing = require("kiwi.renderer.packing")
local Passes = require("kiwi.renderer.passes")
local PassRegistry = require("kiwi.renderer.pass_registry")
local Extensions = require("kiwi.renderer.extensions")
local PassMetrics = require("kiwi.renderer.pass_metrics")
local GpuTiming = require("kiwi.renderer.gpu_timing")
local Invalidation = require("kiwi.renderer.invalidation")
local Inspector = require("kiwi.renderer.inspector")
local Resources = require("kiwi.renderer.resources")
local ShaderLoader = require("kiwi.renderer.shader_loader")
local ShaderReloader = require("kiwi.renderer.shader_reloader")
local Layout = require("kiwi.text.layout")

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

function Renderer.new(context, font, model, options)
  options = options or {}
  local root = os.getenv("KIWI_ROOT") or "."
  local builtin_shader_path = root .. "/src/kiwi/renderer/terminal.wgsl"
  local development_mode = options.development_mode == true
  if development_mode then
    assert(type(options.development_shader_path) == "string" and #options.development_shader_path > 0, "development shader mode needs an explicit shader path")
  end
  local extensions = options.extensions or {}
  assert(type(extensions) == "table", "renderer extensions must be a table")
  local shader_path = development_mode and options.development_shader_path or builtin_shader_path
  local pass_metrics_enabled = options.pass_metrics_enabled == true
  local inspector_enabled = options.inspector_enabled == true
  local extension_manager = Extensions.new({
    enabled = options.extensions_enabled,
    diagnostic_limit = options.extension_diagnostic_limit,
    diagnostic_message_limit = options.extension_diagnostic_message_limit,
    pass_limit = options.extension_pass_limit,
    animation_hz = options.extension_animation_hz,
  })
  Packing.assert_layout()
  local self = setmetatable({
    context = context,
    native = context.native,
    font = font,
    layout = Layout.new(font),
    capacity = model.columns * model.rows,
    glyph_capacity = model.columns * model.rows * 8,
    cells = ffi.new("KiwiGlyphInstance[?]", model.columns * model.rows),
    glyphs = ffi.new("KiwiTextGlyphInstance[?]", model.columns * model.rows * 8),
    frame = ffi.new("KiwiFrameUniform[1]"),
    resource_registry = Resources.new(context:next_renderer_generation()),
    resource_handles = {},
    frame_time = 0,
    shader_path = shader_path,
    extensions = extensions,
    extension_manager = extension_manager,
    pass_metrics = PassMetrics.new({ enabled = pass_metrics_enabled }),
    invalidation = Invalidation.new(),
    inspector_enabled = inspector_enabled,
    inspector_selected_pass = options.inspector_selected_pass,
    diagnostics = {
      cells_uploaded = 0,
      bytes_uploaded = 0,
      dirty_cells = 0,
      dirty_ranges = 0,
      full_update = false,
      glyph_instances_uploaded = 0,
      glyph_bytes_uploaded = 0,
      glyph_instances_dropped = 0,
      rows_reshaped = 0,
      shaping_rows_invalidated = 0,
      runs_reshaped = 0,
      glyphs_produced = 0,
      visible_shaped_runs = 0,
      visible_shaped_glyphs = 0,
      shaping_cpu_ms = 0,
      shape_cache_hits = 0,
      shape_cache_misses = 0,
      atlas_uploads = 0,
      draw_calls = 0,
      extensions = extension_manager:snapshot(),
      gpu_timing = { enabled = false, status = "not initialized", samples = {}, history = {} },
    },
  }, Renderer)
  self.shader_loader = ShaderLoader.native(context, self.resource_registry)
  self.invalidation:request("terminal")
  self.shader_reloader = ShaderReloader.new({
    enabled = development_mode,
    paths = development_mode and { shader_path } or {},
    loader = self.shader_loader,
    poll_interval = options.shader_reload_interval,
  })
  local ok, result = xpcall(function()
    self:create_resources(model)
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
  return self.resource_registry:own_native(label, buffer, self.native.lib.wgpuBufferRelease, self.native.lib.wgpuBufferDestroy)
end

function Renderer:create_resources(model)
  local api = self.native.lib
  local c = self.native.constants
  self.cell_buffer = self:create_buffer("terminal-cell-storage", self.capacity * Packing.glyph_instance_size, c.buffer_usage_storage + c.buffer_usage_copy_dst)
  self.glyph_buffer = self:create_buffer("terminal-shaped-glyph-storage", self.glyph_capacity * Packing.text_glyph_instance_size, c.buffer_usage_storage + c.buffer_usage_copy_dst)
  self.frame_buffer = self:create_buffer("terminal-frame-uniform", ffi.sizeof("KiwiFrameUniform"), c.buffer_usage_uniform + c.buffer_usage_copy_dst)

  local atlas = self.font.glyph_cache.atlas

  local texture_descriptor = ffi.new("WGPUTextureDescriptor")
  texture_descriptor.label = string_view("dynamic-glyph-atlas")
  texture_descriptor.usage = c.texture_usage_copy_dst + c.texture_usage_texture_binding
  texture_descriptor.dimension = c.texture_dimension_2d
  texture_descriptor.size.width = atlas.width
  texture_descriptor.size.height = atlas.height
  texture_descriptor.size.depthOrArrayLayers = 1
  texture_descriptor.format = c.texture_format_r8_unorm
  texture_descriptor.mipLevelCount = 1
  texture_descriptor.sampleCount = 1
  self.atlas_texture = assert_handle(api.wgpuDeviceCreateTexture(self.context.device, texture_descriptor), "glyph atlas texture creation")
  self.resource_registry:own_native("dynamic-glyph-atlas", self.atlas_texture, api.wgpuTextureRelease, api.wgpuTextureDestroy)

  self:upload_atlas()

  self.atlas_view = assert_handle(api.wgpuTextureCreateView(self.atlas_texture, nil), "glyph atlas view creation")
  self.resource_registry:own_native("glyph-atlas-view", self.atlas_view, api.wgpuTextureViewRelease)
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
  self.resource_registry:own_native("glyph-atlas-sampler", self.sampler, api.wgpuSamplerRelease)

  local entries = ffi.new("WGPUBindGroupLayoutEntry[5]")
  entries[0].binding = 0
  entries[0].visibility = c.shader_stage_vertex
  entries[0].buffer.type = c.buffer_binding_readonly_storage
  entries[1].binding = 1
  entries[1].visibility = c.shader_stage_vertex
  entries[1].buffer.type = c.buffer_binding_readonly_storage
  entries[2].binding = 2
  entries[2].visibility = c.shader_stage_fragment
  entries[2].texture.sampleType = c.texture_sample_type_float
  entries[2].texture.viewDimension = c.texture_view_dimension_2d
  entries[3].binding = 3
  entries[3].visibility = c.shader_stage_fragment
  entries[3].sampler.type = c.sampler_binding_filtering
  entries[4].binding = 4
  entries[4].visibility = c.shader_stage_vertex + c.shader_stage_fragment
  entries[4].buffer.type = c.buffer_binding_uniform
  entries[4].buffer.minBindingSize = ffi.sizeof("KiwiFrameUniform")
  local layout_descriptor = ffi.new("WGPUBindGroupLayoutDescriptor")
  layout_descriptor.label = string_view("terminal-bindings")
  layout_descriptor.entryCount = 5
  layout_descriptor.entries = entries
  self.bind_group_layout = assert_handle(api.wgpuDeviceCreateBindGroupLayout(self.context.device, layout_descriptor), "terminal bind-group layout creation")
  self.resource_registry:own_native("terminal-bindings", self.bind_group_layout, api.wgpuBindGroupLayoutRelease)

  local layouts = ffi.new("WGPUBindGroupLayout[1]", self.bind_group_layout)
  local pipeline_layout_descriptor = ffi.new("WGPUPipelineLayoutDescriptor")
  pipeline_layout_descriptor.label = string_view("terminal-pipeline-layout")
  pipeline_layout_descriptor.bindGroupLayoutCount = 1
  pipeline_layout_descriptor.bindGroupLayouts = layouts
  self.pipeline_layout = assert_handle(api.wgpuDeviceCreatePipelineLayout(self.context.device, pipeline_layout_descriptor), "terminal pipeline layout creation")
  self.resource_registry:own_native("terminal-pipeline-layout", self.pipeline_layout, api.wgpuPipelineLayoutRelease)

  local bind_entries = ffi.new("WGPUBindGroupEntry[5]")
  bind_entries[0].binding = 0
  bind_entries[0].buffer = self.cell_buffer
  bind_entries[0].size = self.capacity * Packing.glyph_instance_size
  bind_entries[1].binding = 1
  bind_entries[1].buffer = self.glyph_buffer
  bind_entries[1].size = self.glyph_capacity * Packing.text_glyph_instance_size
  bind_entries[2].binding = 2
  bind_entries[2].textureView = self.atlas_view
  bind_entries[3].binding = 3
  bind_entries[3].sampler = self.sampler
  bind_entries[4].binding = 4
  bind_entries[4].buffer = self.frame_buffer
  bind_entries[4].size = ffi.sizeof("KiwiFrameUniform")
  local bind_group_descriptor = ffi.new("WGPUBindGroupDescriptor")
  bind_group_descriptor.label = string_view("terminal-bind-group")
  bind_group_descriptor.layout = self.bind_group_layout
  bind_group_descriptor.entryCount = 5
  bind_group_descriptor.entries = bind_entries
  self.bind_group = assert_handle(api.wgpuDeviceCreateBindGroup(self.context.device, bind_group_descriptor), "terminal bind-group creation")
  self.resource_registry:own_native("terminal-bind-group", self.bind_group, api.wgpuBindGroupRelease)

  self:register_semantic_resources(model)
  self.pass_registry = PassRegistry.new({
    metrics = self.pass_metrics,
    on_optional_failure = function(pass, phase, message)
      self.extension_manager:disable_pass(pass, phase, message)
      self.diagnostics.extensions = self.extension_manager:snapshot()
      self:invalidate("extension")
    end,
  })
  for _, pass in ipairs(Passes.build(self)) do
    self.pass_registry:register(pass)
  end
  self:register_extension_passes()
  self.pass_registry:initialize(self)
  self.diagnostics.extensions = self.extension_manager:snapshot()
  self.gpu_timing = GpuTiming.new(self.context, self.pass_registry.passes)
  self.diagnostics.gpu_timing = self.gpu_timing:snapshot()
  self.shader_reloader:track(self.pass_registry.passes)
end

function Renderer:register_extension_passes()
  local extensions = self.extension_manager:register(self.extensions, self.pass_registry.passes)
  for _, pass in ipairs(extensions) do
    self.pass_registry:register(pass)
  end
end

function Renderer:create_pipeline(label, vertex_entry, fragment_entry, shader)
  local api = self.native.lib
  local c = self.native.constants
  local target = ffi.new("WGPUColorTargetState[1]")
  target[0].format = self.context.surface_format
  target[0].writeMask = c.color_write_all
  local fragment = ffi.new("WGPUFragmentState")
  fragment.module = shader.handle
  fragment.entryPoint = string_view(fragment_entry)
  fragment.targetCount = 1
  fragment.targets = target
  local descriptor = ffi.new("WGPURenderPipelineDescriptor")
  descriptor.label = string_view(label)
  descriptor.layout = self.pipeline_layout
  descriptor.vertex.module = shader.handle
  descriptor.vertex.entryPoint = string_view(vertex_entry)
  descriptor.primitive.topology = c.primitive_triangle_list
  descriptor.primitive.frontFace = c.front_face_ccw
  descriptor.primitive.cullMode = c.cull_none
  descriptor.multisample.count = 1
  descriptor.multisample.mask = 0xffffffff
  descriptor.fragment = fragment
  self.native.surface.kiwi_surface_clear_error()
  local pipeline = assert_handle(api.wgpuDeviceCreateRenderPipeline(self.context.device, descriptor), "render pipeline creation for " .. label)
  api.wgpuInstanceProcessEvents(self.context.instance)
  local native_error = ffi.string(self.native.surface.kiwi_surface_last_error())
  if #native_error > 0 then
    self.native.surface.kiwi_surface_clear_error()
    api.wgpuRenderPipelineRelease(pipeline)
    error("render pipeline creation for " .. label .. " with shader module " .. shader.id .. " for pass " .. shader.pass .. " failed: " .. native_error)
  end
  return self.resource_registry:own_native(label, pipeline, api.wgpuRenderPipelineRelease)
end

function Renderer:release_native(handle)
  self.resource_registry:release_native(handle)
end

function Renderer:load_shader(id, pass)
  return self.shader_loader:load({
    id = id,
    pass = pass,
    path = self.shader_path,
  })
end

function Renderer:shader_reload_enabled()
  return self.shader_reloader:is_enabled()
end

function Renderer:reload_shaders(force)
  return self.shader_reloader:reload(self, self.pass_registry.passes, force == true)
end

function Renderer:poll_shader_reload(time)
  return self.shader_reloader:poll(self, self.pass_registry.passes, time)
end

function Renderer:resize(previous, current)
  assert(type(previous) == "table" and type(current) == "table", "renderer resize needs previous and current descriptors")
  self.pass_registry:resize(self, previous, current)
end

function Renderer:invalidate(reason)
  self.invalidation:request(reason)
end

function Renderer:schedule_animation(reason, now, delay)
  return self.invalidation:schedule(reason, now, delay)
end

function Renderer:schedule_extension_animation(pass, delay)
  return self.extension_manager:request_animation(pass, self.frame_time, delay, function(reason, now, accepted_delay)
    return self:schedule_animation(reason, now, accepted_delay)
  end)
end

function Renderer:needs_render(now)
  return self.invalidation:due(now)
end

function Renderer:next_render_deadline()
  return self.invalidation:next_deadline()
end

function Renderer:invalidation_snapshot()
  return self.invalidation:snapshot()
end

function Renderer:select_inspector_pass(name)
  assert(name == nil or type(name) == "string", "inspector pass selection must be a string or nil")
  self.inspector_selected_pass = name
end

function Renderer:inspector_snapshot()
  if not self.inspector_enabled then return { enabled = false, passes = {} } end
  return Inspector.build(self, self.inspector_selected_pass)
end

function Renderer:resource_descriptor(kind, access, fields)
  fields.kind = kind
  fields.access = access
  return fields
end

function Renderer:register_semantic_resources(model)
  local registry = self.resource_registry
  local handles = self.resource_handles
  local function register(name, access, fields)
    handles[name] = registry:register(name, self:resource_descriptor(name, access, fields))
  end
  local atlas = self.font.glyph_cache.atlas
  register("terminal.cells", "read", {
    columns = model.columns,
    rows = model.rows,
    capacity = self.capacity,
    instance_bytes = Packing.glyph_instance_size,
  })
  register("text.shaped_glyphs", "read", {
    capacity = self.glyph_capacity,
    count = self.glyph_count or 0,
    instance_bytes = Packing.text_glyph_instance_size,
  })
  register("terminal.cursor", "read", {
    column = model.cursor.column,
    row = model.cursor.row,
    visible = model.cursor.visible ~= false,
  })
  register("terminal.damage", "read", { cells = 0, ranges = 0, full = false })
  register("frame.viewport", "read", {
    columns = model.columns,
    rows = model.rows,
    drawable_width = self.context.width,
    drawable_height = self.context.height,
    content_scale = self.font.content_scale or 1,
  })
  register("frame.timing", "read", { time = self.frame_time, delta = 0 })
  register("text.alpha_atlas", "read", {
    width = atlas.width,
    height = atlas.height,
    format = "r8unorm",
    generation = self.atlas_generation or 0,
  })
  register("surface.color", "write", { format = self.context.surface_format })
end

function Renderer:refresh_semantic_resources(model, time, delta)
  local registry = self.resource_registry
  local handles = self.resource_handles
  local atlas = self.font.glyph_cache.atlas
  registry:update(handles["terminal.cells"], self:resource_descriptor("terminal.cells", "read", {
    columns = model.columns,
    rows = model.rows,
    capacity = self.capacity,
    instance_bytes = Packing.glyph_instance_size,
  }))
  registry:update(handles["text.shaped_glyphs"], self:resource_descriptor("text.shaped_glyphs", "read", {
    capacity = self.glyph_capacity,
    count = self.glyph_count or 0,
    instance_bytes = Packing.text_glyph_instance_size,
  }))
  registry:update(handles["terminal.cursor"], self:resource_descriptor("terminal.cursor", "read", {
    column = model.cursor.column,
    row = model.cursor.row,
    visible = model.cursor.visible ~= false,
  }))
  registry:update(handles["terminal.damage"], self:resource_descriptor("terminal.damage", "read", {
    cells = self.diagnostics.dirty_cells,
    ranges = self.diagnostics.dirty_ranges,
    full = self.diagnostics.full_update,
  }))
  registry:update(handles["frame.viewport"], self:resource_descriptor("frame.viewport", "read", {
    columns = model.columns,
    rows = model.rows,
    drawable_width = self.context.width,
    drawable_height = self.context.height,
    content_scale = self.font.content_scale or 1,
  }))
  registry:update(handles["frame.timing"], self:resource_descriptor("frame.timing", "read", { time = time, delta = delta }))
  registry:update(handles["text.alpha_atlas"], self:resource_descriptor("text.alpha_atlas", "read", {
    width = atlas.width,
    height = atlas.height,
    format = "r8unorm",
    generation = self.atlas_generation or 0,
  }))
  registry:update(handles["surface.color"], self:resource_descriptor("surface.color", "write", { format = self.context.surface_format }))
end

function Renderer:resolve_pass_resources(pass_info)
  local resolved = {}
  for _, name in ipairs(pass_info.reads) do
    resolved[name] = self.resource_registry:resolve(self.resource_handles[name], "read")
  end
  for _, name in ipairs(pass_info.writes) do
    resolved[name] = self.resource_registry:resolve(self.resource_handles[name], "write")
  end
  return resolved
end

function Renderer:upload_atlas()
  local api = self.native.lib
  local c = self.native.constants
  local cache = self.font.glyph_cache
  local atlas = cache.atlas
  local texture_destination = ffi.new("WGPUTexelCopyTextureInfo")
  texture_destination.texture = self.atlas_texture
  texture_destination.aspect = c.texture_aspect_all
  local texture_layout = ffi.new("WGPUTexelCopyBufferLayout")
  texture_layout.bytesPerRow = atlas.width
  texture_layout.rowsPerImage = atlas.height
  local texture_extent = ffi.new("WGPUExtent3D")
  texture_extent.width = atlas.width
  texture_extent.height = atlas.height
  texture_extent.depthOrArrayLayers = 1
  api.wgpuQueueWriteTexture(self.context.queue, texture_destination, cache.pixels, cache.pixel_bytes, texture_layout, texture_extent)
  self.atlas_generation = cache.generation
  self.diagnostics.atlas_uploads = self.diagnostics.atlas_uploads + 1
end

function Renderer:pack_cell(model, index)
  local column, row = model:position(index)
  local cell = model.cells[index]
  local instance = self.cells[index]
  instance.x = column
  instance.y = row
  instance.fg = color_to_u32(cell.fg)
  instance.bg = color_to_u32(cell.bg)
  instance.flags = cell.flags
  if self.font.glyph_cache then
    instance.u0 = 0
    instance.v0 = 0
    instance.u1 = 0
    instance.v1 = 0
    instance.glyph = 0
    return
  end
  local glyph, glyph_key = select_glyph(self.font.atlas, cell.glyph)
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

function Renderer:pack_shaped_glyph(glyph, index)
  local instance = self.glyphs[index]
  instance.x = glyph.x
  instance.y = glyph.y
  instance.width = glyph.width
  instance.height = glyph.height
  instance.u0 = glyph.u0
  instance.v0 = glyph.v0
  instance.u1 = glyph.u1
  instance.v1 = glyph.v1
  instance.fg = color_to_u32(glyph.fg)
  instance.flags = glyph.flags
  instance.glyph = glyph.glyph_id
  instance.cluster = glyph.cluster_column
end

function Renderer:update_model(model)
  local damage = model.damage
  local shaped_glyphs = self.layout:update(model)
  local ranges = damage:ranges()
  if #ranges > 0 then self:invalidate("terminal") end
  self.diagnostics.dirty_cells = damage.dirty_count
  self.diagnostics.dirty_ranges = #ranges
  self.diagnostics.full_update = damage.full
  self.diagnostics.cells_uploaded = 0
  self.diagnostics.bytes_uploaded = 0
  self.diagnostics.rows_reshaped = self.layout.stats.rows_reshaped
  self.diagnostics.shaping_rows_invalidated = self.layout.stats.rows_invalidated
  self.diagnostics.runs_reshaped = self.layout.stats.runs_reshaped
  self.diagnostics.glyphs_produced = self.layout.stats.glyphs_produced
  self.diagnostics.visible_shaped_runs = self.layout.stats.visible_runs
  self.diagnostics.visible_shaped_glyphs = self.layout.stats.visible_glyphs
  self.diagnostics.shaping_cpu_ms = self.layout.stats.shaping_cpu_ms
  self.diagnostics.shape_cache_hits = self.layout.stats.cache_hits
  self.diagnostics.shape_cache_misses = self.layout.stats.cache_misses
  for _, range in ipairs(ranges) do
    for index = range.first, range.first + range.count - 1 do
      self:pack_cell(model, index)
    end
    local bytes = range.count * Packing.glyph_instance_size
    self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.cell_buffer, range.first * Packing.glyph_instance_size, self.cells + range.first, bytes)
    self.diagnostics.cells_uploaded = self.diagnostics.cells_uploaded + range.count
    self.diagnostics.bytes_uploaded = self.diagnostics.bytes_uploaded + bytes
  end
  self.diagnostics.glyph_instances_uploaded = 0
  self.diagnostics.glyph_bytes_uploaded = 0
  self.diagnostics.glyph_instances_dropped = 0
  if self.layout.stats.rows_reshaped > 0 then
    local glyph_count = math.min(#shaped_glyphs, self.glyph_capacity)
    for index = 1, glyph_count do self:pack_shaped_glyph(shaped_glyphs[index], index - 1) end
    if glyph_count > 0 then
      local bytes = glyph_count * Packing.text_glyph_instance_size
      self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.glyph_buffer, 0, self.glyphs, bytes)
      self.diagnostics.glyph_instances_uploaded = glyph_count
      self.diagnostics.glyph_bytes_uploaded = bytes
    end
    self.diagnostics.glyph_instances_dropped = #shaped_glyphs - glyph_count
    self.glyph_count = glyph_count
  end
  if self.atlas_generation ~= self.font.glyph_cache.generation then self:upload_atlas() end
  self:refresh_semantic_resources(model, self.frame_time, 0)
  damage:clear()
end

function Renderer:update_frame(model, time, debug_dirty, debug_boundaries)
  local delta = math.max(0, time - self.frame_time)
  self.frame_time = time
  self.frame[0].columns = model.columns
  self.frame[0].rows = model.rows
  self.frame[0].cursor_column = model.cursor.column
  self.frame[0].cursor_row = model.cursor.row
  self.frame[0].time = time
  self.frame[0].show_dirty = debug_dirty and 1 or 0
  self.frame[0].show_boundaries = debug_boundaries and 1 or 0
  self.frame[0].cursor_visible = model.cursor.visible == false and 0 or 1
  self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.frame_buffer, 0, self.frame, ffi.sizeof("KiwiFrameUniform"))
  self:refresh_semantic_resources(model, time, delta)
end

function Renderer:encode_semantic_pass(pass_info, encoder, view, model, resources)
  assert(resources["surface.color"] ~= nil, "semantic pass requires a presentation target")
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
  if self.gpu_timing then descriptor.timestampWrites = self.gpu_timing:writes(pass_info.name) end
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
  if self.gpu_timing then self.gpu_timing:begin_frame() end
  self.pass_registry:begin_frame()
  self.pass_registry:prepare(self, model)
  self.pass_registry:encode(self, encoder, view, model)
  self.pass_registry:end_frame()
  if self.gpu_timing then self.gpu_timing:resolve(encoder) end
  if self.pass_metrics.enabled then self.diagnostics.pass_cpu = self.pass_metrics:snapshot() end
  self.diagnostics.extensions = self.extension_manager:snapshot()
  local commands = ffi.new("WGPUCommandBuffer[1]")
  commands[0] = assert_handle(self.native.lib.wgpuCommandEncoderFinish(encoder, nil), "command-buffer creation")
  self.native.lib.wgpuQueueSubmit(self.context.queue, 1, commands)
  if self.gpu_timing then self.gpu_timing:submit() end
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
  if self.gpu_timing then
    self.gpu_timing:poll()
    self.diagnostics.gpu_timing = self.gpu_timing:snapshot()
  end
  local native_error = ffi.string(self.native.surface.kiwi_surface_last_error())
  if #native_error > 0 then
    return false, "native GPU error: " .. native_error
  end
  self.diagnostics.draw_calls = self.pass_registry:count()
  self.invalidation:consume_success(time)
  self.extension_manager:consume_animations(time)
  self.diagnostics.invalidation = self:invalidation_snapshot()
  self.diagnostics.extensions = self.extension_manager:snapshot()
  if self.inspector_enabled then self.diagnostics.inspector = self:inspector_snapshot() end
  return true
end

function Renderer:destroy()
  local pass_error
  if self.gpu_timing then self.gpu_timing:destroy() end
  if self.pass_registry then
    local ok, message = pcall(self.pass_registry.shutdown, self.pass_registry, self)
    if not ok then pass_error = message end
  end
  local resource_ok, resource_error = pcall(self.resource_registry.destroy, self.resource_registry)
  if pass_error then error(pass_error, 2) end
  if not resource_ok then error(resource_error, 2) end
end

return Renderer
