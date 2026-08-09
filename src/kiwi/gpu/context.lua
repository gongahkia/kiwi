local ffi = require("ffi")
local wgpu = require("kiwi.ffi.wgpu")

local Context = {}
Context.__index = Context

local function string_view(value)
  return ffi.new("WGPUStringView", { data = value, length = #value })
end

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

function Context.new(window)
  local self = setmetatable({ window = window, native = wgpu, callbacks = {}, errors = {} }, Context)
  local api = wgpu.lib
  local constants = wgpu.constants

  local instance_descriptor = ffi.new("WGPUInstanceDescriptor")
  self.instance = assert_handle(api.wgpuCreateInstance(instance_descriptor), "wgpuCreateInstance")
  self.surface = assert_handle(wgpu.surface.kiwi_surface_from_glfw(self.instance, window.handle), "kiwi_surface_from_glfw: " .. ffi.string(wgpu.surface.kiwi_surface_last_error()))

  local adapter_result = {}
  self.callbacks.adapter = ffi.cast("WGPURequestAdapterCallback", function(status, adapter, message)
    adapter_result.status = status
    adapter_result.adapter = adapter
    adapter_result.message = message_text(message)
  end)
  local adapter_options = ffi.new("WGPURequestAdapterOptions")
  adapter_options.featureLevel = 2
  adapter_options.backendType = constants.backend_vulkan
  adapter_options.compatibleSurface = self.surface
  local adapter_callback = ffi.new("WGPURequestAdapterCallbackInfo")
  adapter_callback.mode = constants.callback_wait_any_only
  adapter_callback.callback = self.callbacks.adapter
  local adapter_future = api.wgpuInstanceRequestAdapter(self.instance, adapter_options, adapter_callback)
  self:wait_for(adapter_future, "adapter request")
  if adapter_result.status ~= constants.request_adapter_success or adapter_result.adapter == nil then
    error("Unable to request a Vulkan-capable adapter: " .. (adapter_result.message or "unknown error"))
  end
  self.adapter = adapter_result.adapter

  local adapter_info = ffi.new("WGPUAdapterInfo")
  if api.wgpuAdapterGetInfo(self.adapter, adapter_info) ~= 1 then
    error("wgpuAdapterGetInfo failed")
  end
  self.adapter_info = {
    vendor = message_text(adapter_info.vendor),
    device = message_text(adapter_info.device),
    description = message_text(adapter_info.description),
    backend = adapter_info.backendType,
  }
  api.wgpuAdapterInfoFreeMembers(adapter_info)

  self.callbacks.device_error = ffi.cast("WGPUUncapturedErrorCallback", function(_, kind, message)
    self.errors[#self.errors + 1] = string.format("WGPU error %d: %s", kind, message_text(message))
  end)
  local device_result = {}
  self.callbacks.device = ffi.cast("WGPURequestDeviceCallback", function(status, device, message)
    device_result.status = status
    device_result.device = device
    device_result.message = message_text(message)
  end)
  local device_descriptor = ffi.new("WGPUDeviceDescriptor")
  device_descriptor.label = string_view("kiwi-m0-device")
  device_descriptor.uncapturedErrorCallbackInfo.callback = self.callbacks.device_error
  local device_callback = ffi.new("WGPURequestDeviceCallbackInfo")
  device_callback.mode = constants.callback_wait_any_only
  device_callback.callback = self.callbacks.device
  local device_future = api.wgpuAdapterRequestDevice(self.adapter, device_descriptor, device_callback)
  self:wait_for(device_future, "device request")
  if device_result.status ~= constants.request_device_success or device_result.device == nil then
    error("Unable to create a wgpu device: " .. (device_result.message or "unknown error"))
  end
  self.device = device_result.device
  self.queue = assert_handle(api.wgpuDeviceGetQueue(self.device), "wgpuDeviceGetQueue")
  self:configure_surface()
  return self
end

function Context:wait_for(future, label)
  local wait = ffi.new("WGPUFutureWaitInfo[1]")
  wait[0].future = future
  local status = self.native.lib.wgpuInstanceWaitAny(self.instance, 1, wait, 10 * 1000 * 1000 * 1000)
  if status ~= self.native.constants.wait_success or wait[0].completed == 0 then
    error("Timed out or failed while waiting for " .. label .. " (WGPU wait status " .. status .. ")")
  end
end

function Context:configure_surface()
  local width, height = self.window:drawable_size()
  if width <= 0 or height <= 0 then
    return false
  end
  local capabilities = ffi.new("WGPUSurfaceCapabilities")
  if self.native.lib.wgpuSurfaceGetCapabilities(self.surface, self.adapter, capabilities) ~= 1 or capabilities.formatCount == 0 then
    error("Unable to query surface capabilities")
  end
  self.surface_format = capabilities.formats[0]
  local config = ffi.new("WGPUSurfaceConfiguration")
  config.device = self.device
  config.format = self.surface_format
  config.usage = self.native.constants.texture_usage_render_attachment
  config.width = width
  config.height = height
  config.alphaMode = self.native.constants.alpha_opaque
  config.presentMode = self.native.constants.present_fifo
  self.native.lib.wgpuSurfaceConfigure(self.surface, config)
  self.native.lib.wgpuSurfaceCapabilitiesFreeMembers(capabilities)
  self.width = width
  self.height = height
  self.window.resized = false
  return true
end

function Context:destroy()
  local api = self.native.lib
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
