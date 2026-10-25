local ffi = require("ffi")
local Resources = require("kiwi.renderer.resources")
local Loader = require("kiwi.renderer.shader_loader")
local Pipeline = require("kiwi.renderer.pipeline")
local Paths = require("kiwi.paths")
local Effect = {}
Effect.__index = Effect
Effect.identity = "fn kiwi_effect(color: vec4<f32>, uv: vec2<f32>, time: f32, resolution: vec2<f32>) -> vec4<f32> { return color; }"
local function view(value) return ffi.new("WGPUStringView", { data = value, length = #value }) end

function Effect.new(context, source)
  assert(source == nil or (type(source) == "string" and #source > 0 and #source <= 64 * 1024 and not source:find("%z")),
    "custom shader source must be bounded NUL-free WGSL")
  local self = setmetatable({ context = context, native = context.native,
    resource_registry = Resources.new(context:next_renderer_generation()) }, Effect)
  local ok, message = pcall(function()
    local api, c = self.native.lib, self.native.constants
    local function own(label, handle, release, destroy)
      assert(handle ~= nil, label .. " creation failed")
      return self.resource_registry:own_native(label, handle, release, destroy)
    end
    local entries = ffi.new("WGPUBindGroupLayoutEntry[3]")
    for index = 0, 2 do entries[index].binding = index; entries[index].visibility = c.shader_stage_fragment end
    entries[0].texture.sampleType = c.texture_sample_type_float
    entries[0].texture.viewDimension = c.texture_view_dimension_2d
    entries[1].sampler.type = c.sampler_binding_filtering
    entries[2].buffer.type = c.buffer_binding_uniform
    entries[2].buffer.minBindingSize = 16
    local layout = ffi.new("WGPUBindGroupLayoutDescriptor", { label = view("surface-effect-bindings"), entryCount = 3, entries = entries })
    self.bind_group_layout = own("effect-bindings", api.wgpuDeviceCreateBindGroupLayout(context.device, layout), api.wgpuBindGroupLayoutRelease)
    local layouts = ffi.new("WGPUBindGroupLayout[1]", self.bind_group_layout)
    local descriptor = ffi.new("WGPUPipelineLayoutDescriptor", { bindGroupLayoutCount = 1, bindGroupLayouts = layouts })
    self.pipeline_layout = own("effect-layout", api.wgpuDeviceCreatePipelineLayout(context.device, descriptor), api.wgpuPipelineLayoutRelease)
    local loader = Loader.native(context, self.resource_registry)
    local definition = { id = "surface-effect", pass = "surface-effect", path = Paths.lua_root() .. "/kiwi/renderer/postprocess.wgsl" }
    local shader = loader:load_source(definition, loader:read(definition) .. "\n" .. (source or Effect.identity))
    self.pipeline = Pipeline.create(self, "surface-effect", "kiwi_vs", "kiwi_fs", shader)
    local sampler = ffi.new("WGPUSamplerDescriptor")
    sampler.addressModeU, sampler.addressModeV, sampler.addressModeW = c.sampler_address_clamp_to_edge, c.sampler_address_clamp_to_edge, c.sampler_address_clamp_to_edge
    sampler.magFilter, sampler.minFilter, sampler.mipmapFilter = c.filter_nearest, c.filter_nearest, c.mipmap_filter_nearest
    sampler.lodMaxClamp, sampler.maxAnisotropy = 1, 1
    self.sampler = own("effect-sampler", api.wgpuDeviceCreateSampler(context.device, sampler), api.wgpuSamplerRelease)
    local buffer = ffi.new("WGPUBufferDescriptor", { size = 16, usage = c.buffer_usage_uniform + c.buffer_usage_copy_dst })
    self.uniform = own("effect-uniform", api.wgpuDeviceCreateBuffer(context.device, buffer), api.wgpuBufferRelease, api.wgpuBufferDestroy)
    self.parameters = ffi.new("float[4]")
    self:resize(context.width, context.height)
  end)
  if not ok then self:destroy(); error(message, 0) end
  return self
end

function Effect:resize(width, height)
  if self.width == width and self.height == height then return end
  local api, c = self.native.lib, self.native.constants
  -- Keep the previous target intact until all replacements exist.
  local registry = Resources.new(self.context:next_renderer_generation())
  local ok, message = pcall(function()
    local descriptor = ffi.new("WGPUTextureDescriptor")
    descriptor.usage = c.texture_usage_render_attachment + c.texture_usage_texture_binding
    descriptor.dimension, descriptor.format = c.texture_dimension_2d, self.context.surface_format
    descriptor.size.width, descriptor.size.height, descriptor.size.depthOrArrayLayers = width, height, 1
    descriptor.mipLevelCount, descriptor.sampleCount = 1, 1
    local texture = api.wgpuDeviceCreateTexture(self.context.device, descriptor)
    assert(texture ~= nil, "effect texture creation failed")
    registry:own_native("effect-texture", texture, api.wgpuTextureRelease, api.wgpuTextureDestroy)
    local target = api.wgpuTextureCreateView(texture, nil)
    assert(target ~= nil, "effect texture view creation failed")
    registry:own_native("effect-view", target, api.wgpuTextureViewRelease)
    local entries = ffi.new("WGPUBindGroupEntry[3]")
    entries[0].binding, entries[0].textureView = 0, target
    entries[1].binding, entries[1].sampler = 1, self.sampler
    entries[2].binding, entries[2].buffer, entries[2].size = 2, self.uniform, 16
    local binding = ffi.new("WGPUBindGroupDescriptor", { layout = self.bind_group_layout, entryCount = 3, entries = entries })
    local group = api.wgpuDeviceCreateBindGroup(self.context.device, binding)
    assert(group ~= nil, "effect bind group creation failed")
    registry:own_native("effect-bind-group", group, api.wgpuBindGroupRelease)
    self.view, self.bind_group = target, group
  end)
  if not ok then registry:destroy(); error(message, 0) end
  if self.target_registry then self.target_registry:destroy() end
  self.target_registry, self.width, self.height = registry, width, height
end

function Effect:encode(encoder, target, time)
  local api, c = self.native.lib, self.native.constants
  self.parameters[0], self.parameters[1], self.parameters[2] = self.width, self.height, time
  self.parameters[3] = self.context.surface_alpha_mode == 3 and 0 or 1
  api.wgpuQueueWriteBuffer(self.context.queue, self.uniform, 0, self.parameters, 16)
  local attachment = ffi.new("WGPURenderPassColorAttachment")
  attachment.view, attachment.depthSlice = target, 0xffffffff
  attachment.loadOp, attachment.storeOp = c.load_clear, c.store_store
  local descriptor = ffi.new("WGPURenderPassDescriptor", { colorAttachmentCount = 1, colorAttachments = attachment })
  local pass = api.wgpuCommandEncoderBeginRenderPass(encoder, descriptor)
  assert(pass ~= nil, "effect render pass creation failed")
  api.wgpuRenderPassEncoderSetPipeline(pass, self.pipeline)
  api.wgpuRenderPassEncoderSetBindGroup(pass, 0, self.bind_group, 0, nil)
  api.wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0)
  api.wgpuRenderPassEncoderEnd(pass)
  api.wgpuRenderPassEncoderRelease(pass)
  self.next_frame = time + 1 / 30
end

function Effect:destroy()
  if self.target_registry then self.target_registry:destroy(); self.target_registry = nil end
  self.resource_registry:destroy()
end
return Effect
