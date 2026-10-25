local ffi = require("ffi")
local Pipeline = {}
local function string_view(value) return ffi.new("WGPUStringView", { data = value, length = #value }) end
local function assert_handle(handle, label) assert(handle ~= nil, label .. " returned a null handle"); return handle end

function Pipeline.create(self, label, vertex_entry, fragment_entry, shader, blend, pipeline_layout)
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


return Pipeline
