local ffi = require("ffi")
local Packing = require("kiwi.renderer.packing")
local PreparedImages = require("kiwi.renderer.prepared_images")

local KittyImages = {}
KittyImages.__index = KittyImages

local function assert_handle(handle, label)
  if handle == nil then error(label .. " returned a null handle") end
  return handle
end

local function string_view(value)
  return ffi.new("WGPUStringView", { data = value, length = #value })
end

local function integer(value, minimum)
  return type(value) == "number" and value % 1 == 0 and value >= minimum
end

local function release(owner, handle)
  if handle ~= nil then owner:release_native(handle) end
end

local function release_entry(owner, entry)
  release(owner, entry.bind_group)
  release(owner, entry.view)
  release(owner, entry.texture)
end

KittyImages.plan = PreparedImages.plan

local function signature(instances)
  local items = {}
  for _, instance in ipairs(instances) do
    items[#items + 1] = table.concat({
      instance.image_id,
      instance.generation or 0,
      instance.placement_id,
      instance.z,
      instance.column,
      instance.columns,
      instance.row,
      instance.row_count,
      instance.source_row,
    }, ":")
  end
  return table.concat(items, ";")
end

local function placement_descriptors(view, textures, images)
  local result = { count = 0 }
  for _, placement in ipairs(view and view.placements or {}) do
    local texture = textures[placement.image_id]
    local image = images[placement.image_id]
    if placement.visible and texture and image and texture.generation == image.generation then
      local first_row
      local last_row
      local visible_rows = 0
      for _, row in ipairs(placement.rows or {}) do
        if integer(row.row, 0) then
          first_row = first_row and math.min(first_row, row.row) or row.row
          last_row = last_row and math.max(last_row, row.row) or row.row
          visible_rows = visible_rows + 1
        end
      end
      if visible_rows > 0 then
        result.count = result.count + 1
        result["placement_" .. result.count] = {
          column = placement.column,
          columns = placement.columns,
          first_row = first_row,
          image_id = placement.image_id,
          last_row = last_row,
          layer = placement.z < 0 and "under" or "over",
          placement_id = placement.placement_id,
          visible_rows = visible_rows,
          z = placement.z,
        }
      end
    end
  end
  return result
end

function KittyImages.new(capacity)
  assert(integer(capacity, 1), "kitty image renderer capacity must be a positive integer")
  return setmetatable({
    capacity = capacity,
    instances = ffi.new("KiwiImageInstance[?]", capacity),
    textures = {},
    blocked = {},
    under = {},
    over = {},
    placements = { count = 0 },
    signature = "",
    uploads = 0,
    initialized = false,
  }, KittyImages)
end

function KittyImages:descriptor()
  local texture_count = 0
  for _ in pairs(self.textures) do texture_count = texture_count + 1 end
  return {
    active = #self.under + #self.over > 0,
    instances = #self.under + #self.over,
    over_instances = #self.over,
    placements = self.placements,
    textures = texture_count,
    under_instances = #self.under,
    uploads = self.uploads,
  }
end

function KittyImages:initialize(owner)
  if self.initialized then return end
  local api = owner.native.lib
  local c = owner.native.constants
  self.instance_buffer = owner:create_buffer(
    "kitty-image-instances",
    self.capacity * Packing.image_instance_size,
    c.buffer_usage_storage + c.buffer_usage_copy_dst
  )

  local sampler_descriptor = ffi.new("WGPUSamplerDescriptor")
  sampler_descriptor.label = string_view("kitty-image-sampler")
  sampler_descriptor.addressModeU = c.sampler_address_clamp_to_edge
  sampler_descriptor.addressModeV = c.sampler_address_clamp_to_edge
  sampler_descriptor.addressModeW = c.sampler_address_clamp_to_edge
  sampler_descriptor.magFilter = c.filter_linear
  sampler_descriptor.minFilter = c.filter_linear
  sampler_descriptor.mipmapFilter = c.mipmap_filter_nearest
  sampler_descriptor.lodMaxClamp = 32
  sampler_descriptor.maxAnisotropy = 1
  self.sampler = assert_handle(api.wgpuDeviceCreateSampler(owner.context.device, sampler_descriptor), "kitty image sampler creation")
  owner.resource_registry:own_native("kitty-image-sampler", self.sampler, api.wgpuSamplerRelease)

  local entries = ffi.new("WGPUBindGroupLayoutEntry[3]")
  entries[0].binding = 0
  entries[0].visibility = c.shader_stage_fragment
  entries[0].texture.sampleType = c.texture_sample_type_float
  entries[0].texture.viewDimension = c.texture_view_dimension_2d
  entries[1].binding = 1
  entries[1].visibility = c.shader_stage_fragment
  entries[1].sampler.type = c.sampler_binding_filtering
  entries[2].binding = 2
  entries[2].visibility = c.shader_stage_vertex
  entries[2].buffer.type = c.buffer_binding_readonly_storage
  entries[2].buffer.minBindingSize = Packing.image_instance_size
  local layout_descriptor = ffi.new("WGPUBindGroupLayoutDescriptor")
  layout_descriptor.label = string_view("kitty-image-bindings")
  layout_descriptor.entryCount = 3
  layout_descriptor.entries = entries
  self.bind_group_layout = assert_handle(api.wgpuDeviceCreateBindGroupLayout(owner.context.device, layout_descriptor), "kitty image bind-group layout creation")
  owner.resource_registry:own_native("kitty-image-bindings", self.bind_group_layout, api.wgpuBindGroupLayoutRelease)

  local layouts = ffi.new("WGPUBindGroupLayout[1]", self.bind_group_layout)
  local pipeline_layout_descriptor = ffi.new("WGPUPipelineLayoutDescriptor")
  pipeline_layout_descriptor.label = string_view("kitty-image-pipeline-layout")
  pipeline_layout_descriptor.bindGroupLayoutCount = 1
  pipeline_layout_descriptor.bindGroupLayouts = layouts
  self.pipeline_layout = assert_handle(api.wgpuDeviceCreatePipelineLayout(owner.context.device, pipeline_layout_descriptor), "kitty image pipeline layout creation")
  owner.resource_registry:own_native("kitty-image-pipeline-layout", self.pipeline_layout, api.wgpuPipelineLayoutRelease)
  self.initialized = true
end

function KittyImages:drain_gpu_releases(owner, graphics)
  local changed = false
  for _, item in ipairs(graphics:take_gpu_releases()) do
    local entry = self.textures[item.id]
    if entry and entry.generation == item.generation then
      release_entry(owner, entry)
      self.textures[item.id] = nil
      changed = true
    end
    self.blocked[item.id] = nil
  end
  return changed
end

function KittyImages:remove_texture(owner, graphics, id, generation, release_gpu)
  local entry = self.textures[id]
  if entry == nil or (generation ~= nil and entry.generation ~= generation) then return false end
  release_entry(owner, entry)
  self.textures[id] = nil
  if release_gpu then graphics:release_gpu_upload(entry.id, entry.generation, "placement-inactive") end
  return true
end

function KittyImages:upload_pixels(owner, texture, image)
  local source_stride = image.width * 4
  local upload_stride = math.ceil(source_stride / 256) * 256
  local pixels = image.pixels
  local upload_bytes = image.bytes
  if upload_stride ~= source_stride then
    upload_bytes = upload_stride * image.height
    pixels = ffi.new("uint8_t[?]", upload_bytes)
    local source = ffi.cast("const uint8_t *", image.pixels)
    for row = 0, image.height - 1 do
      ffi.copy(pixels + row * upload_stride, source + row * source_stride, source_stride)
    end
  end
  local destination = ffi.new("WGPUTexelCopyTextureInfo")
  destination.texture = texture
  destination.aspect = owner.native.constants.texture_aspect_all
  local layout = ffi.new("WGPUTexelCopyBufferLayout")
  layout.bytesPerRow = upload_stride
  layout.rowsPerImage = image.height
  local extent = ffi.new("WGPUExtent3D")
  extent.width = image.width
  extent.height = image.height
  extent.depthOrArrayLayers = 1
  owner.native.lib.wgpuQueueWriteTexture(owner.context.queue, destination, pixels, upload_bytes, layout, extent)
end

function KittyImages:create_texture(owner, image)
  local api = owner.native.lib
  local c = owner.native.constants
  local label = string.format("kitty-image-%d-%d", image.id, image.generation)
  local entry = { frame_revision = image.frame_revision, generation = image.generation, id = image.id }
  local ok, result = xpcall(function()
    local texture_descriptor = ffi.new("WGPUTextureDescriptor")
    texture_descriptor.label = string_view(label .. "-texture")
    texture_descriptor.usage = c.texture_usage_copy_dst + c.texture_usage_texture_binding
    texture_descriptor.dimension = c.texture_dimension_2d
    texture_descriptor.size.width = image.width
    texture_descriptor.size.height = image.height
    texture_descriptor.size.depthOrArrayLayers = 1
    texture_descriptor.format = c.texture_format_rgba8_unorm
    texture_descriptor.mipLevelCount = 1
    texture_descriptor.sampleCount = 1
    entry.texture = assert_handle(api.wgpuDeviceCreateTexture(owner.context.device, texture_descriptor), "kitty image texture creation")
    owner.resource_registry:own_native(label .. "-texture", entry.texture, api.wgpuTextureRelease, api.wgpuTextureDestroy)
    self:upload_pixels(owner, entry.texture, image)

    entry.view = assert_handle(api.wgpuTextureCreateView(entry.texture, nil), "kitty image texture view creation")
    owner.resource_registry:own_native(label .. "-view", entry.view, api.wgpuTextureViewRelease)
    local entries = ffi.new("WGPUBindGroupEntry[3]")
    entries[0].binding = 0
    entries[0].textureView = entry.view
    entries[1].binding = 1
    entries[1].sampler = self.sampler
    entries[2].binding = 2
    entries[2].buffer = self.instance_buffer
    entries[2].size = self.capacity * Packing.image_instance_size
    local descriptor = ffi.new("WGPUBindGroupDescriptor")
    descriptor.label = string_view(label .. "-bind-group")
    descriptor.layout = self.bind_group_layout
    descriptor.entryCount = 3
    descriptor.entries = entries
    entry.bind_group = assert_handle(api.wgpuDeviceCreateBindGroup(owner.context.device, descriptor), "kitty image bind-group creation")
    owner.resource_registry:own_native(label .. "-bind-group", entry.bind_group, api.wgpuBindGroupRelease)
    return entry
  end, debug.traceback)
  if ok then return result end
  pcall(release_entry, owner, entry)
  error(result, 0)
end

function KittyImages:ensure_texture(owner, graphics, image)
  local existing = self.textures[image.id]
  if existing and existing.generation == image.generation then
    if existing.frame_revision ~= image.frame_revision then
      self:upload_pixels(owner, existing.texture, image)
      existing.frame_revision = image.frame_revision
      self.uploads = self.uploads + 1
      return existing, true
    end
    return existing, false
  end
  if existing then self:remove_texture(owner, graphics, image.id, nil, true) end
  if self.blocked[image.id] == image.generation then return nil, false end
  local registered, reason = graphics:register_gpu_upload(image.id, image.generation, image.frame_bytes or image.bytes)
  if not registered then
    self.blocked[image.id] = image.generation
    return nil, false, reason
  end
  self:drain_gpu_releases(owner, graphics)
  local ok, entry = xpcall(function() return self:create_texture(owner, image) end, debug.traceback)
  if not ok then
    graphics:release_gpu_upload(image.id, image.generation, "texture-create-failed")
    self:drain_gpu_releases(owner, graphics)
    error(entry, 0)
  end
  self.textures[image.id] = entry
  self.uploads = self.uploads + 1
  return entry, true
end

function KittyImages:sync(owner, model)
  local plan = PreparedImages.prepare(model)
  if plan == nil then return false end
  local graphics = plan.graphics
  self.graphics = graphics
  local placement_view = plan.placement_view
  local under, over = plan.under, plan.over
  local wanted = plan.wanted
  local wanted_ids = plan.wanted_ids
  local changed = self:drain_gpu_releases(owner, graphics)
  local resident_ids = {}
  for id in pairs(self.textures) do resident_ids[#resident_ids + 1] = id end
  table.sort(resident_ids)
  for _, id in ipairs(resident_ids) do
    local entry = self.textures[id]
    if entry and not wanted[id] then changed = self:remove_texture(owner, graphics, id, entry.generation, true) or changed end
  end

  local descriptors = plan.descriptors
  for _, id in ipairs(wanted_ids) do
    local image = descriptors[id]
    if image then
      local _, uploaded = self:ensure_texture(owner, graphics, image)
      changed = uploaded or changed
    end
  end
  changed = self:drain_gpu_releases(owner, graphics) or changed

  local visible_under = {}
  local visible_over = {}
  local function collect(source, target)
    for _, item in ipairs(source) do
      if #visible_under + #visible_over >= self.capacity then break end
      local texture = self.textures[item.image_id]
      local image = descriptors[item.image_id]
      if texture and image and texture.generation == image.generation then
        graphics:touch_gpu_upload(image.id, image.generation)
        item.generation = image.generation
        item.texture = texture
        target[#target + 1] = item
      end
    end
  end
  collect(under, visible_under)
  collect(over, visible_over)
  local next_signature = signature(visible_under) .. "|" .. signature(visible_over)
  if next_signature ~= self.signature then
    local index = 0
    for _, layer in ipairs({ visible_under, visible_over }) do
      for _, item in ipairs(layer) do
        local instance = self.instances[index]
        instance.x = item.column / model.columns * 2 - 1
        instance.y = 1 - item.row / model.rows * 2
        instance.width = item.columns / model.columns * 2
        instance.height = -2 / model.rows
        instance.u0 = 0
        instance.v0 = item.source_row / item.row_count
        instance.u1 = 1
        instance.v1 = (item.source_row + 1) / item.row_count
        item.index = index
        index = index + 1
      end
    end
    if index > 0 then
      owner.native.lib.wgpuQueueWriteBuffer(owner.context.queue, self.instance_buffer, 0, self.instances, index * Packing.image_instance_size)
    end
    self.signature = next_signature
    changed = true
  else
    local index = 0
    for _, layer in ipairs({ visible_under, visible_over }) do
      for _, item in ipairs(layer) do
        item.index = index
        index = index + 1
      end
    end
  end
  self.under = visible_under
  self.over = visible_over
  self.placements = placement_descriptors(placement_view, self.textures, descriptors)
  return changed
end

function KittyImages:instances_for(layer)
  return layer == "under" and self.under or self.over
end

function KittyImages:encode(layer, pass)
  for _, item in ipairs(self:instances_for(layer)) do
    pass.native.lib.wgpuRenderPassEncoderSetBindGroup(pass.handle, 0, item.texture.bind_group, 0, nil)
    pass.native.lib.wgpuRenderPassEncoderDraw(pass.handle, 6, 1, 0, item.index)
  end
end

function KittyImages:shutdown(owner)
  if not self.initialized then return end
  local graphics = self.graphics
  local ids = {}
  for id in pairs(self.textures) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local entry = self.textures[id]
    release_entry(owner, entry)
    self.textures[id] = nil
    if graphics then graphics:release_gpu_upload(entry.id, entry.generation, "renderer-destroyed") end
  end
  if graphics then graphics:take_gpu_releases() end
  self.under = {}
  self.over = {}
  self.placements = { count = 0 }
  self.initialized = false
end

return KittyImages
