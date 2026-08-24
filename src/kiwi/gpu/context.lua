local ffi = require("ffi")
local wgpu = require("kiwi.ffi.wgpu")

local Context = {}
Context.__index = Context

local function message_text(view)
  if view.data == nil then
    return "no message supplied"
  end
  return ffi.string(view.data, tonumber(view.length))
end

local function assert_handle(handle, label)
  if handle == nil then
    error(label .. " returned a null handle")
  end
  return handle
end

function Context.parse_framebuffer_expected_rgb(value)
  if value == nil or value == "" then return nil end
  assert(type(value) == "string", "expected framebuffer RGB must be a string")
  local red, green, blue = value:match("^(%d+),(%d+),(%d+)$")
  red, green, blue = tonumber(red), tonumber(green), tonumber(blue)
  for _, channel in ipairs({ red or -1, green or -1, blue or -1 }) do
    assert(channel ~= nil and channel >= 0 and channel <= 255 and channel % 1 == 0,
      "expected framebuffer RGB must be R,G,B with byte channels")
  end
  return { red = red, green = green, blue = blue }
end

function Context.select_surface_format(formats, count, constants)
  assert(formats ~= nil and type(count) == "number" and count >= 1, "surface needs at least one format")
  constants = constants or wgpu.constants
  for _, preferred in ipairs({ constants.texture_format_bgra8_unorm_srgb, constants.texture_format_rgba8_unorm_srgb }) do
    for index = 0, count - 1 do
      if tonumber(formats[index]) == preferred then return preferred, true end
    end
  end
  return tonumber(formats[0]), false
end

function Context.new(host, window, options)
  options = options or {}
  assert(type(host) == "table" and type(host.create_surface) == "function" and type(host.set_drawable_size) == "function", "GPU context needs a host surface provider")
  assert(options.gpu_timestamps == nil or type(options.gpu_timestamps) == "boolean", "GPU timestamp option must be a boolean")
  assert(options.framebuffer_capture == nil or type(options.framebuffer_capture) == "boolean", "framebuffer capture option must be a boolean")
  assert(options.framebuffer_expected_rgb == nil or type(options.framebuffer_expected_rgb) == "string", "expected framebuffer RGB must be a string")
  local self = setmetatable({
    host = host,
    window = window,
    native = wgpu,
    framebuffer_capture_requested = options.framebuffer_capture == true,
    framebuffer_expected_rgb = Context.parse_framebuffer_expected_rgb(options.framebuffer_expected_rgb),
    framebuffer_samples = {},
  }, Context)
  local ok, result = xpcall(function()
    local api = wgpu.lib
    local instance_descriptor = ffi.new("WGPUInstanceDescriptor")
    self.instance = assert_handle(api.wgpuCreateInstance(instance_descriptor), "wgpuCreateInstance")
    local surface = host.create_surface(self.instance, window)
    local surface_error = host.surface_error and host.surface_error() or ffi.string(wgpu.surface.kiwi_surface_last_error())
    self.surface = assert_handle(surface, "host surface creation: " .. surface_error)

    self.adapter = wgpu.surface.kiwi_request_adapter_sync(self.instance, self.surface)
    if self.adapter == nil then
      error("Unable to request a " .. ffi.string(wgpu.surface.kiwi_native_backend_name()) .. " adapter: " .. ffi.string(wgpu.surface.kiwi_surface_last_error()))
    end

    local adapter_info = ffi.new("WGPUAdapterInfo")
    if api.wgpuAdapterGetInfo(self.adapter, adapter_info) ~= 1 then
      error("wgpuAdapterGetInfo failed")
    end
    self.adapter_info = {
      vendor = message_text(adapter_info.vendor),
      device = message_text(adapter_info.device),
      description = message_text(adapter_info.description),
      backend = adapter_info.backendType,
      backend_name = adapter_info.backendType == wgpu.surface.kiwi_native_backend_type()
        and ffi.string(wgpu.surface.kiwi_native_backend_name()) or ("backend-" .. adapter_info.backendType),
    }
    api.wgpuAdapterInfoFreeMembers(adapter_info)
    self.timestamp_query_supported = api.wgpuAdapterHasFeature(self.adapter, 9) ~= 0
    self.timestamp_query_requested = options.gpu_timestamps == true
    if self.timestamp_query_requested and self.timestamp_query_supported then
      self.device = wgpu.surface.kiwi_request_timestamp_device_sync(self.instance, self.adapter)
      if self.device ~= nil then
        self.timestamp_query_enabled = true
        self.timestamp_query_reason = "enabled"
      else
        self.timestamp_query_reason = ffi.string(wgpu.surface.kiwi_surface_last_error())
      end
    elseif not self.timestamp_query_supported then
      self.timestamp_query_reason = "adapter does not expose timestamp-query"
    else
      self.timestamp_query_reason = "disabled by configuration"
    end
    if self.device == nil then
      self.device = wgpu.surface.kiwi_request_device_sync(self.instance, self.adapter)
    end
    if self.device == nil then
      error("Unable to create a wgpu device: " .. ffi.string(wgpu.surface.kiwi_surface_last_error()))
    end
    self.queue = assert_handle(api.wgpuDeviceGetQueue(self.device), "wgpuDeviceGetQueue")
    self:configure_surface()
  end, debug.traceback)
  if not ok then
    self:destroy()
    error(result, 0)
  end
  return self
end

function Context:timestamp_status()
  return {
    requested = self.timestamp_query_requested == true,
    supported = self.timestamp_query_supported == true,
    enabled = self.timestamp_query_enabled == true,
    reason = self.timestamp_query_reason,
  }
end

function Context:configure_surface()
  local width, height = self.window:drawable_size()
  if width <= 0 or height <= 0 then
    return false
  end
  if not self.host.set_drawable_size(self.window, width, height) then
    local surface_error = self.host.surface_error and self.host.surface_error() or ffi.string(self.native.surface.kiwi_surface_last_error())
    error("Unable to update native surface drawable size: " .. surface_error)
  end
  local capabilities = ffi.new("WGPUSurfaceCapabilities")
  if self.native.lib.wgpuSurfaceGetCapabilities(self.surface, self.adapter, capabilities) ~= 1 or capabilities.formatCount == 0 or capabilities.alphaModeCount == 0 then
    error("Unable to query surface capabilities")
  end
  local supports_copy_src = math.floor(tonumber(capabilities.usages) / self.native.constants.texture_usage_copy_src) % 2 == 1
  if self.framebuffer_capture_requested and not supports_copy_src then
    self.native.lib.wgpuSurfaceCapabilitiesFreeMembers(capabilities)
    error("surface does not expose copy-src usage required for framebuffer capture")
  end
  self.surface_format, self.surface_is_srgb = Context.select_surface_format(capabilities.formats, tonumber(capabilities.formatCount), self.native.constants)
  local config = ffi.new("WGPUSurfaceConfiguration")
  config.device = self.device
  config.format = self.surface_format
  config.usage = self.native.constants.texture_usage_render_attachment
  if self.framebuffer_capture_requested then config.usage = config.usage + self.native.constants.texture_usage_copy_src end
  config.width = width
  config.height = height
  config.alphaMode = capabilities.alphaModes[0]
  config.presentMode = self.native.constants.present_fifo
  self.native.lib.wgpuSurfaceConfigure(self.surface, config)
  self.native.lib.wgpuSurfaceCapabilitiesFreeMembers(capabilities)
  if self.framebuffer_capture ~= nil then
    self.native.surface.kiwi_framebuffer_capture_destroy(self.framebuffer_capture)
    self.framebuffer_capture = nil
  end
  if self.framebuffer_capture_requested then
    self.native.surface.kiwi_surface_clear_error()
    self.framebuffer_capture = self.native.surface.kiwi_framebuffer_capture_new(self.instance, self.device, width, height, self.surface_format)
    if self.framebuffer_capture == nil then
      error("Unable to create framebuffer capture: " .. ffi.string(self.native.surface.kiwi_surface_last_error()))
    end
    if self.framebuffer_expected_rgb then
      local expected = self.framebuffer_expected_rgb
      assert(self.native.surface.kiwi_framebuffer_capture_set_expected_rgb(self.framebuffer_capture,
        expected.red, expected.green, expected.blue, 4) ~= 0, "could not configure framebuffer RGB expectation")
    end
    self.framebuffer_samples = {}
  end
  self.width = width
  self.height = height
  self.window.resized = false
  return true
end

local function presentation_frame_assertion(context, frame)
  assert(type(frame) == "table" and frame.context == context, "presentation frame belongs to another context")
  assert(frame.state == "acquired", "presentation frame is no longer acquired")
end

local function release_presentation_frame(context, frame)
  local api = context.native.lib
  if frame.encoder ~= nil then
    api.wgpuCommandEncoderRelease(frame.encoder)
    frame.encoder = nil
  end
  if frame.view ~= nil then
    api.wgpuTextureViewRelease(frame.view)
    frame.view = nil
  end
  if frame.texture ~= nil then
    api.wgpuTextureRelease(frame.texture)
    frame.texture = nil
  end
end

-- A presentation frame is intentionally opaque to the compositor. The current
-- implementation carries WGPU handles, but a host-owned renderer can provide
-- another frame type without teaching window/session code about its graphics
-- API.
function Context:begin_presentation_frame()
  local width, height = self.window:drawable_size()
  if self.window.minimized or width <= 0 or height <= 0 then return nil, "zero-sized drawable" end
  if self.window.resized or width ~= self.width or height ~= self.height then
    self.window.resized = true
    if not self:configure_surface() then return nil, "zero-sized drawable" end
  end
  local api = self.native.lib
  local constants = self.native.constants
  local surface_texture = ffi.new("WGPUSurfaceTexture")
  api.wgpuSurfaceGetCurrentTexture(self.surface, surface_texture)
  if surface_texture.status == constants.surface_occluded then
    if surface_texture.texture ~= nil then api.wgpuTextureRelease(surface_texture.texture) end
    return nil, "surface occluded"
  end
  if surface_texture.status ~= constants.surface_success_optimal and surface_texture.status ~= constants.surface_success_suboptimal then
    if surface_texture.texture ~= nil then api.wgpuTextureRelease(surface_texture.texture) end
    return nil, "surface acquire status " .. tonumber(surface_texture.status)
  end
  local frame = {
    backend = "wgpu",
    context = self,
    state = "acquired",
    surface_status = tonumber(surface_texture.status),
    texture = surface_texture.texture,
  }
  local ok, result = xpcall(function()
    frame.view = assert_handle(api.wgpuTextureCreateView(frame.texture, nil), "surface texture view creation")
    frame.encoder = assert_handle(api.wgpuDeviceCreateCommandEncoder(self.device, nil), "command encoder creation")
  end, debug.traceback)
  if ok then return frame end
  release_presentation_frame(self, frame)
  frame.state = "aborted"
  error(result, 0)
end

function Context:abort_presentation_frame(frame)
  presentation_frame_assertion(self, frame)
  release_presentation_frame(self, frame)
  frame.state = "aborted"
  return true
end

function Context:present_presentation_frame(frame)
  presentation_frame_assertion(self, frame)
  local api = self.native.lib
  local completed = false
  local ok, presented, present_reason = xpcall(function()
    local commands = assert_handle(api.wgpuCommandEncoderFinish(frame.encoder, nil), "command-buffer creation")
    local command_list = ffi.new("WGPUCommandBuffer[1]")
    command_list[0] = commands
    api.wgpuQueueSubmit(self.queue, 1, command_list)
    api.wgpuCommandBufferRelease(commands)
    api.wgpuCommandEncoderRelease(frame.encoder)
    frame.encoder = nil
    api.wgpuTextureViewRelease(frame.view)
    frame.view = nil
    local present_status = api.wgpuSurfacePresent(self.surface)
    api.wgpuTextureRelease(frame.texture)
    frame.texture = nil
    frame.state = "presented"
    completed = true
    if frame.surface_status == self.native.constants.surface_success_suboptimal then self.window.resized = true end
    if present_status ~= 1 then return nil, "surface present status " .. tonumber(present_status) end
    local native_error = ffi.string(self.native.surface.kiwi_surface_last_error())
    if #native_error > 0 then return nil, "native GPU error: " .. native_error end
    return true
  end, debug.traceback)
  if not ok then
    if not completed then
      release_presentation_frame(self, frame)
      frame.state = "aborted"
    end
    error(presented, 0)
  end
  return presented, present_reason
end

function Context:begin_framebuffer_capture(frame)
  if self.framebuffer_capture == nil then return false end
  assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0, "framebuffer capture frame must be a non-negative integer")
  return self.native.surface.kiwi_framebuffer_capture_begin(self.framebuffer_capture, frame) ~= 0
end

function Context:abort_framebuffer_capture()
  if self.framebuffer_capture ~= nil then self.native.surface.kiwi_framebuffer_capture_abort(self.framebuffer_capture) end
end

function Context:encode_framebuffer_capture(encoder, texture)
  if self.framebuffer_capture ~= nil then
    self.native.surface.kiwi_framebuffer_capture_encode(self.framebuffer_capture, encoder, texture)
  end
end

function Context:submit_framebuffer_capture()
  if self.framebuffer_capture ~= nil then self.native.surface.kiwi_framebuffer_capture_submit(self.framebuffer_capture) end
end

function Context:poll_framebuffer_capture()
  if self.framebuffer_capture == nil then return {} end
  local sample = ffi.new("KiwiFramebufferSample[1]")
  local captured = {}
  while true do
    local status = self.native.surface.kiwi_framebuffer_capture_poll(self.framebuffer_capture, sample)
    if status == 0 then break end
    if status < 0 then error("Framebuffer capture failed: " .. ffi.string(self.native.surface.kiwi_surface_last_error())) end
    local item = {
      blue_dominant_pixels = tonumber(sample[0].blue_dominant_pixels),
      checksum = tostring(sample[0].checksum),
      frame = tonumber(sample[0].frame),
      expected_rgb_pixels = tonumber(sample[0].expected_rgb_pixels),
      modal_rgb = tonumber(sample[0].modal_rgb),
      modal_rgb_pixels = tonumber(sample[0].modal_rgb_pixels),
      opaque_pixels = tonumber(sample[0].opaque_pixels),
      red_dominant_pixels = tonumber(sample[0].red_dominant_pixels),
    }
    captured[#captured + 1] = item
    self.framebuffer_samples[#self.framebuffer_samples + 1] = item
    if #self.framebuffer_samples > 32 then table.remove(self.framebuffer_samples, 1) end
  end
  return captured
end

function Context:framebuffer_capture_snapshot()
  local samples = {}
  for index, sample in ipairs(self.framebuffer_samples) do
    samples[index] = {
      blue_dominant_pixels = sample.blue_dominant_pixels,
      checksum = sample.checksum,
      frame = sample.frame,
      expected_rgb_pixels = sample.expected_rgb_pixels,
      modal_rgb = sample.modal_rgb,
      modal_rgb_pixels = sample.modal_rgb_pixels,
      opaque_pixels = sample.opaque_pixels,
      red_dominant_pixels = sample.red_dominant_pixels,
    }
  end
  return {
    dropped = self.framebuffer_capture and tonumber(self.native.surface.kiwi_framebuffer_capture_dropped(self.framebuffer_capture)) or 0,
    expected_rgb = self.framebuffer_expected_rgb and {
      blue = self.framebuffer_expected_rgb.blue,
      green = self.framebuffer_expected_rgb.green,
      red = self.framebuffer_expected_rgb.red,
      tolerance = 4,
    } or nil,
    pending = self.framebuffer_capture and tonumber(self.native.surface.kiwi_framebuffer_capture_pending(self.framebuffer_capture)) or 0,
    samples = samples,
  }
end

function Context:next_renderer_generation()
  self.renderer_generation = (self.renderer_generation or 0) + 1
  return self.renderer_generation
end

function Context:probe_timestamp_queries()
  if not self.timestamp_query_supported then
    return false, "adapter does not expose timestamp-query"
  end
  self.native.surface.kiwi_surface_clear_error()
  local ok = self.native.surface.kiwi_timestamp_query_probe(self.instance, self.adapter) ~= 0
  return ok, ffi.string(self.native.surface.kiwi_surface_last_error())
end

function Context:destroy()
  local api = self.native.lib
  if self.framebuffer_capture ~= nil then
    self.native.surface.kiwi_framebuffer_capture_destroy(self.framebuffer_capture)
    self.framebuffer_capture = nil
  end
  if self.surface ~= nil then
    api.wgpuSurfaceUnconfigure(self.surface)
    api.wgpuSurfaceRelease(self.surface)
    self.surface = nil
  end
  if self.queue ~= nil then
    api.wgpuQueueRelease(self.queue)
    self.queue = nil
  end
  if self.device ~= nil then
    api.wgpuDeviceDestroy(self.device)
    api.wgpuDeviceRelease(self.device)
    self.device = nil
  end
  if self.adapter ~= nil then
    api.wgpuAdapterRelease(self.adapter)
    self.adapter = nil
  end
  if self.instance ~= nil then
    api.wgpuInstanceRelease(self.instance)
    self.instance = nil
  end
end

return Context
