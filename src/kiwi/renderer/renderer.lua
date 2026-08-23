local ffi = require("ffi")
local Packing = require("kiwi.renderer.packing")
local Paths = require("kiwi.paths")
local Passes = require("kiwi.renderer.passes")
local PassRegistry = require("kiwi.renderer.pass_registry")
local Extensions = require("kiwi.renderer.extensions")
local PassMetrics = require("kiwi.renderer.pass_metrics")
local PassBudgets = require("kiwi.renderer.pass_budgets")
local GpuTiming = require("kiwi.renderer.gpu_timing")
local CommandRegions = require("kiwi.renderer.command_regions")
local Color = require("kiwi.renderer.color")
local Hyperlink = require("kiwi.renderer.hyperlink")
local Invalidation = require("kiwi.renderer.invalidation")
local Inspector = require("kiwi.renderer.inspector")
local KittyImages = require("kiwi.renderer.kitty_images")
local PreparedFrame = require("kiwi.renderer.prepared_frame")
local PreparedImages = require("kiwi.renderer.prepared_images")
local Resources = require("kiwi.renderer.resources")
local Search = require("kiwi.renderer.search")
local Selection = require("kiwi.renderer.selection")
local Scrollbar = require("kiwi.renderer.scrollbar")
local ShaderLoader = require("kiwi.renderer.shader_loader")
local ShaderReloader = require("kiwi.renderer.shader_reloader")

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

local cursor_blink_interval = 0.5

Renderer.select_glyph = PreparedFrame.select_glyph
Renderer.pack_cell = PreparedFrame.pack_cell
Renderer.pack_shaped_glyph = PreparedFrame.pack_shaped_glyph

function Renderer.new(context, font, model, options)
  options = options or {}
  local lua_root = Paths.lua_root()
  local builtin_shader_path = lua_root .. "/kiwi/renderer/terminal.wgsl"
  local image_shader_path = lua_root .. "/kiwi/renderer/kitty_images.wgsl"
  local development_mode = options.development_mode == true
  if development_mode then
    assert(type(options.development_shader_path) == "string" and #options.development_shader_path > 0, "development shader mode needs an explicit shader path")
  end
  local extensions = options.extensions or {}
  assert(type(extensions) == "table", "renderer extensions must be a table")
  local shader_path = development_mode and options.development_shader_path or builtin_shader_path
  local pass_metrics_enabled = options.pass_metrics_enabled == true
  local pass_budgets_enabled = options.pass_budgets_enabled == true
  assert(options.pass_budgets_enabled == nil or type(options.pass_budgets_enabled) == "boolean", "pass budget enablement must be a boolean")
  assert(options.command_region_visual_enabled == nil or type(options.command_region_visual_enabled) == "boolean", "command region visual enablement must be a boolean")
  Scrollbar.validate_policy(options.scrollbar_policy)
  assert(options.text_backend == nil or type(options.text_backend) == "string", "text backend selection must be a string")
  local inspector_enabled = options.inspector_enabled == true
  local placement_limit = model.kitty_placements and model.kitty_placements.limit or 256
  local placement_rows = model.kitty_placements and model.kitty_placements.max_rows or 256
  local prepared_frame = PreparedFrame.new(font, model, options)
  local extension_manager = Extensions.new({
    enabled = options.extensions_enabled,
    diagnostic_limit = options.extension_diagnostic_limit,
    diagnostic_message_limit = options.extension_diagnostic_message_limit,
    pass_limit = options.extension_pass_limit,
    animation_hz = options.extension_animation_hz,
  })
  local self = setmetatable({
    context = context,
    native = context.native,
    font = font,
    layout = prepared_frame.layout,
    text_backend = prepared_frame.text_backend,
    capacity = prepared_frame.capacity,
    glyph_capacity = prepared_frame.glyph_capacity,
    cells = prepared_frame.cells,
    glyphs = prepared_frame.glyphs,
    frame = prepared_frame.frame,
    prepared_frame = prepared_frame,
    resource_registry = Resources.new(context:next_renderer_generation()),
    resource_handles = {},
    frame_time = 0,
    shader_path = shader_path,
    image_shader_path = image_shader_path,
    extensions = extensions,
    extension_manager = extension_manager,
    pass_metrics = PassMetrics.new({ enabled = pass_metrics_enabled or pass_budgets_enabled }),
    pass_budgets = PassBudgets.new({ enabled = pass_budgets_enabled, warning_limit = options.pass_budget_warning_limit }),
    invalidation = Invalidation.new(),
    inspector_enabled = inspector_enabled,
    inspector_selected_pass = options.inspector_selected_pass,
    selection_color = prepared_frame.selection_color,
    search_color = prepared_frame.search_color,
    hyperlink_color = prepared_frame.hyperlink_color,
    command_region_visual_enabled = prepared_frame.command_region_visual_enabled,
    command_region_color = prepared_frame.command_region_color,
    scrollbar_policy = prepared_frame.scrollbar_policy,
    kitty_images = KittyImages.new(placement_limit * placement_rows),
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
      pass_budgets = { enabled = false, warnings = {}, passes = {} },
      gpu_timing = { enabled = false, status = "not initialized", samples = {}, history = {} },
      text_backend = prepared_frame.text_backend:descriptor(),
    },
  }, Renderer)
  self.diagnostics.kitty_images = self.kitty_images:descriptor()
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
  self.pass_budgets:register(self.pass_registry.passes)
  self.diagnostics.pass_budgets = self.pass_budgets:snapshot()
  self.pass_registry:initialize(self)
  self.diagnostics.extensions = self.extension_manager:snapshot()
  self.gpu_timing = GpuTiming.new(self.context, self.pass_registry.passes)
  self.diagnostics.gpu_timing = self.gpu_timing:snapshot()
  self.shader_reloader:track(self.pass_registry.passes)
end

function Renderer:pass_budget_snapshot(name)
  return self.pass_budgets:pass_snapshot(name)
end

function Renderer:register_extension_passes()
  local extensions = self.extension_manager:register(self.extensions, self.pass_registry.passes)
  for _, pass in ipairs(extensions) do
    self.pass_registry:register(pass)
  end
end

function Renderer:create_pipeline(label, vertex_entry, fragment_entry, shader, blend, pipeline_layout)
  local api = self.native.lib
  local c = self.native.constants
  local target = ffi.new("WGPUColorTargetState[1]")
  target[0].format = self.context.surface_format
  target[0].writeMask = c.color_write_all
  if blend ~= nil then
    assert(blend == "alpha", "unknown render pipeline blend mode " .. tostring(blend))
    local state = ffi.new("WGPUBlendState[1]")
    state[0].color.operation = c.blend_operation_add
    state[0].color.srcFactor = c.blend_factor_src_alpha
    state[0].color.dstFactor = c.blend_factor_one_minus_src_alpha
    state[0].alpha.operation = c.blend_operation_add
    state[0].alpha.srcFactor = c.blend_factor_one
    state[0].alpha.dstFactor = c.blend_factor_one_minus_src_alpha
    target[0].blend = state
  end
  local fragment = ffi.new("WGPUFragmentState")
  fragment.module = shader.handle
  fragment.entryPoint = string_view(fragment_entry)
  fragment.targetCount = 1
  fragment.targets = target
  local descriptor = ffi.new("WGPURenderPipelineDescriptor")
  descriptor.label = string_view(label)
  descriptor.layout = pipeline_layout or self.pipeline_layout
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

function Renderer:load_shader(id, pass, path)
  return self.shader_loader:load({
    id = id,
    pass = pass,
    path = path or self.shader_path,
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

function Renderer:cursor_descriptor(model)
  return PreparedFrame.cursor_descriptor(model)
end

function Renderer:can_present(model)
  return not self.context.window.minimized and (model.modes == nil or model.modes.synchronized_output ~= true)
end

function Renderer:cursor_blink_delay(model)
  local cursor = Renderer.cursor_descriptor(self, model)
  if cursor.visible and cursor.blink and Renderer.can_present(self, model) then return cursor_blink_interval end
  return nil
end

function Renderer:selection_descriptor(model)
  return Selection.descriptor(model, self.selection_color)
end

function Renderer:search_descriptor(model)
  return Search.descriptor(model, self.search_color)
end

function Renderer:hyperlink_descriptor(model)
  return Hyperlink.descriptor(model, self.hyperlink_color)
end

function Renderer:command_regions_descriptor(model)
  return CommandRegions.descriptor(model)
end

function Renderer:scrollbar_descriptor(model)
  return Scrollbar.descriptor(model, self.scrollbar_policy)
end

function Renderer:update_command_regions(model)
  local descriptor = self:command_regions_descriptor(model)
  if not CommandRegions.same(self.command_regions, descriptor) then self:invalidate("command_regions") end
  return descriptor
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
  register("terminal.cursor", "read", self:cursor_descriptor(model))
  self.selection = self:selection_descriptor(model)
  register("terminal.selection", "read", self.selection)
  self.search = self:search_descriptor(model)
  register("terminal.search", "read", self.search)
  self.hyperlinks = self:hyperlink_descriptor(model)
  register("terminal.hyperlinks", "read", self.hyperlinks)
  self.command_regions = self:command_regions_descriptor(model)
  register("terminal.command_regions", "read", self.command_regions)
  self.scrollbar = self:scrollbar_descriptor(model)
  register("terminal.scrollbar", "read", self.scrollbar)
  register("terminal.kitty_images", "read", self.kitty_images:descriptor())
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

function Renderer:refresh_semantic_resources(model, time, delta, selection, search, hyperlinks, command_regions, scrollbar)
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
  registry:update(handles["terminal.cursor"], self:resource_descriptor("terminal.cursor", "read", self:cursor_descriptor(model)))
  self.selection = selection or self:selection_descriptor(model)
  registry:update(handles["terminal.selection"], self:resource_descriptor("terminal.selection", "read", self.selection))
  self.search = search or self:search_descriptor(model)
  registry:update(handles["terminal.search"], self:resource_descriptor("terminal.search", "read", self.search))
  self.hyperlinks = hyperlinks or self:hyperlink_descriptor(model)
  registry:update(handles["terminal.hyperlinks"], self:resource_descriptor("terminal.hyperlinks", "read", self.hyperlinks))
  self.command_regions = command_regions or self:command_regions_descriptor(model)
  registry:update(handles["terminal.command_regions"], self:resource_descriptor("terminal.command_regions", "read", self.command_regions))
  self.scrollbar = scrollbar or self:scrollbar_descriptor(model)
  registry:update(handles["terminal.scrollbar"], self:resource_descriptor("terminal.scrollbar", "read", self.scrollbar))
  registry:update(handles["terminal.kitty_images"], self:resource_descriptor("terminal.kitty_images", "read", self.kitty_images:descriptor()))
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

function Renderer:upload_atlas(update)
  assert(type(update) == "table" and update.data ~= nil, "atlas upload needs prepared atlas data")
  local api = self.native.lib
  local c = self.native.constants
  local texture_destination = ffi.new("WGPUTexelCopyTextureInfo")
  texture_destination.texture = self.atlas_texture
  texture_destination.aspect = c.texture_aspect_all
  local texture_layout = ffi.new("WGPUTexelCopyBufferLayout")
  texture_layout.bytesPerRow = update.width
  texture_layout.rowsPerImage = update.height
  local texture_extent = ffi.new("WGPUExtent3D")
  texture_extent.width = update.width
  texture_extent.height = update.height
  texture_extent.depthOrArrayLayers = 1
  api.wgpuQueueWriteTexture(self.context.queue, texture_destination, update.data, update.byte_count, texture_layout, texture_extent)
  self.diagnostics.atlas_uploads = self.diagnostics.atlas_uploads + 1
end

function Renderer:update_model(model)
  local image_plan = PreparedImages.prepare(model)
  if self.kitty_images:sync(self, model, image_plan) then self:invalidate("kitty_images") end
  self.diagnostics.kitty_images = self.kitty_images:descriptor()
  local plan = self.prepared_frame:prepare_model(model)
  plan.images = image_plan
  if #plan.cell_updates > 0 then self:invalidate("terminal") end
  local uploaded, upload_error = xpcall(function()
    for _, update in ipairs(plan.cell_updates) do
      self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.cell_buffer,
        update.first * Packing.glyph_instance_size, update.data, update.byte_count)
      plan.diagnostics.cells_uploaded = plan.diagnostics.cells_uploaded + update.cell_count
      plan.diagnostics.bytes_uploaded = plan.diagnostics.bytes_uploaded + update.byte_count
    end
    if plan.glyph_update and plan.glyph_update.byte_count > 0 then
      self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.glyph_buffer, 0,
        plan.glyph_update.data, plan.glyph_update.byte_count)
      plan.diagnostics.glyph_bytes_uploaded = plan.glyph_update.byte_count
    end
    if plan.atlas_update then self:upload_atlas(plan.atlas_update) end
  end, debug.traceback)
  if not uploaded then
    self.prepared_frame:discard_model(plan)
    error(upload_error, 0)
  end
  if not CommandRegions.same(self.command_regions, plan.descriptors.command_regions) then self:invalidate("command_regions") end
  self.prepared_frame:commit_model(plan)
  self.glyph_count = self.prepared_frame.glyph_count
  self.atlas_generation = self.prepared_frame.atlas_generation
  for name, value in pairs(plan.diagnostics) do self.diagnostics[name] = value end
  self.diagnostics.text_backend = self.text_backend:descriptor()
  self:refresh_semantic_resources(model, self.frame_time, 0,
    plan.descriptors.selection, plan.descriptors.search, plan.descriptors.hyperlinks,
    plan.descriptors.command_regions, plan.descriptors.scrollbar)
end

function Renderer:update_frame(model, time, debug_dirty, debug_boundaries)
  local frame = self.prepared_frame:prepare_frame(model, time, debug_dirty, debug_boundaries, {
    surface_is_srgb = self.context.surface_is_srgb,
  })
  self.frame_time = frame.time
  self.native.lib.wgpuQueueWriteBuffer(self.context.queue, self.frame_buffer, 0, frame.data, frame.byte_count)
  self:refresh_semantic_resources(model, frame.time, frame.delta,
    frame.selection, frame.search, frame.hyperlinks, frame.command_regions, frame.scrollbar)
end

function Renderer:configure_pass_viewport(pass)
  local viewport = self.frame_viewport
  if viewport == nil then return end
  self.native.lib.wgpuRenderPassEncoderSetViewport(
    pass,
    viewport.x,
    viewport.y,
    viewport.width,
    viewport.height,
    0,
    1
  )
  self.native.lib.wgpuRenderPassEncoderSetScissorRect(pass, viewport.x, viewport.y, viewport.width, viewport.height)
end

function Renderer:pass_load_op(pass_info)
  if self.frame_clear == false and pass_info.load_op == self.native.constants.load_clear then
    return self.native.constants.load_load
  end
  return pass_info.load_op
end

function Renderer:encode_semantic_pass(pass_info, encoder, view, model, resources)
  assert(resources["surface.color"] ~= nil, "semantic pass requires a presentation target")
  local attachment = ffi.new("WGPURenderPassColorAttachment")
  attachment.view = view
  attachment.depthSlice = 0xffffffff
  attachment.loadOp = self:pass_load_op(pass_info)
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
  self:configure_pass_viewport(pass)
  self.native.lib.wgpuRenderPassEncoderSetPipeline(pass, pass_info.pipeline)
  self.native.lib.wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nil)
  self.native.lib.wgpuRenderPassEncoderDraw(pass, 6, pass_info.instances(model), 0, 0)
  self.native.lib.wgpuRenderPassEncoderEnd(pass)
  self.native.lib.wgpuRenderPassEncoderRelease(pass)
end

function Renderer:encode_kitty_image_pass(pass_info, encoder, view, model, resources)
  assert(resources["surface.color"] ~= nil, "kitty image pass requires a presentation target")
  local attachment = ffi.new("WGPURenderPassColorAttachment")
  attachment.view = view
  attachment.depthSlice = 0xffffffff
  attachment.loadOp = self:pass_load_op(pass_info)
  attachment.storeOp = self.native.constants.store_store
  local descriptor = ffi.new("WGPURenderPassDescriptor")
  descriptor.label = string_view(pass_info.name)
  descriptor.colorAttachmentCount = 1
  descriptor.colorAttachments = attachment
  if self.gpu_timing then descriptor.timestampWrites = self.gpu_timing:writes(pass_info.name) end
  local pass = assert_handle(self.native.lib.wgpuCommandEncoderBeginRenderPass(encoder, descriptor), "render-pass creation for " .. pass_info.name)
  self:configure_pass_viewport(pass)
  self.native.lib.wgpuRenderPassEncoderSetPipeline(pass, pass_info.pipeline)
  self.kitty_images:encode(pass_info.image_layer, { handle = pass, native = self.native })
  self.native.lib.wgpuRenderPassEncoderEnd(pass)
  self.native.lib.wgpuRenderPassEncoderRelease(pass)
end

function Renderer:encode_into(presentation, model, time, debug_dirty, debug_boundaries, options)
  assert(type(presentation) == "table" and presentation.backend == "wgpu" and presentation.encoder ~= nil and presentation.view ~= nil, "WGPU renderer needs an acquired WGPU presentation frame")
  options = options or {}
  assert(options.clear == nil or type(options.clear) == "boolean", "renderer frame clear option must be a boolean")
  local viewport = options.viewport
  if viewport ~= nil then
    assert(type(viewport) == "table", "renderer frame viewport must be a table")
    for _, name in ipairs({ "x", "y", "width", "height" }) do
      assert(type(viewport[name]) == "number" and viewport[name] >= 0 and viewport[name] % 1 == 0, "renderer frame viewport " .. name .. " must be a non-negative integer")
    end
    assert(viewport.width >= 1 and viewport.height >= 1, "renderer frame viewport dimensions must be positive")
  end
  self:update_frame(model, time, debug_dirty, debug_boundaries)
  self.frame_clear = options.clear ~= false
  self.frame_viewport = viewport
  if self.gpu_timing then self.gpu_timing:begin_frame() end
  self.pass_registry:begin_frame()
  self.pass_registry:prepare(self, model)
  self.pass_registry:encode(self, presentation.encoder, presentation.view, model)
  self.pass_registry:end_frame()
  if self.gpu_timing then self.gpu_timing:resolve(presentation.encoder) end
  if self.pass_metrics.enabled then self.diagnostics.pass_cpu = self.pass_metrics:snapshot() end
  self.frame_clear = nil
  self.frame_viewport = nil
end

function Renderer:finish_frame(model, time)
  if self.gpu_timing then self.gpu_timing:submit() end
  self.native.lib.wgpuInstanceProcessEvents(self.context.instance)
  if self.gpu_timing then
    self.gpu_timing:poll()
    self.diagnostics.gpu_timing = self.gpu_timing:snapshot()
  end
  self.pass_budgets:observe(self.diagnostics.pass_cpu, self.diagnostics.gpu_timing, time)
  self.diagnostics.pass_budgets = self.pass_budgets:snapshot()
  self.diagnostics.draw_calls = self.pass_registry:count()
  self.invalidation:consume_success(time)
  self.extension_manager:consume_animations(time)
  local cursor_blink_delay = self:cursor_blink_delay(model)
  if cursor_blink_delay then self:schedule_animation("cursor", time, cursor_blink_delay) end
  if model.kitty_graphics and type(model.kitty_graphics.animation_delay) == "function" then
    local kitty_animation_delay = model.kitty_graphics:animation_delay(time)
    if kitty_animation_delay then self:schedule_animation("kitty_images", time, kitty_animation_delay) end
  end
  self.diagnostics.invalidation = self:invalidation_snapshot()
  self.diagnostics.extensions = self.extension_manager:snapshot()
  if self.inspector_enabled then self.diagnostics.inspector = self:inspector_snapshot() end
end

function Renderer:render(model, time, debug_dirty, debug_boundaries)
  local presentation, reason = self.context:begin_presentation_frame()
  if presentation == nil then return false, reason end
  local ok, result = xpcall(function()
    self:encode_into(presentation, model, time, debug_dirty, debug_boundaries, { clear = true })
  end, debug.traceback)
  if not ok then
    self.context:abort_presentation_frame(presentation)
    error(result, 0)
  end
  self.diagnostics.extensions = self.extension_manager:snapshot()
  local presented, present_reason = self.context:present_presentation_frame(presentation)
  if not presented then return false, present_reason end
  self:finish_frame(model, time)
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
  if self.prepared_frame then self.prepared_frame:destroy() end
  if pass_error then error(pass_error, 2) end
  if not resource_ok then error(resource_error, 2) end
end

return Renderer
