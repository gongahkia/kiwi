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

function Context.new(window)
  local self = setmetatable({ window = window, native = wgpu }, Context)
  local ok, result = xpcall(function()
    local api = wgpu.lib
    local instance_descriptor = ffi.new("WGPUInstanceDescriptor")
    self.instance = assert_handle(api.wgpuCreateInstance(instance_descriptor), "wgpuCreateInstance")
    self.surface = assert_handle(wgpu.surface.kiwi_surface_from_glfw(self.instance, window.handle), "kiwi_surface_from_glfw: " .. ffi.string(wgpu.surface.kiwi_surface_last_error()))

    self.adapter = wgpu.surface.kiwi_request_adapter_sync(self.instance, self.surface)
    if self.adapter == nil then
      error("Unable to request a Vulkan-capable adapter: " .. ffi.string(wgpu.surface.kiwi_surface_last_error()))
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
      backend_name = adapter_info.backendType == 6 and "Vulkan" or ("backend-" .. adapter_info.backendType),
    }
    api.wgpuAdapterInfoFreeMembers(adapter_info)
    self.timestamp_query_supported = api.wgpuAdapterHasFeature(self.adapter, 9) ~= 0

    self.device = wgpu.surface.kiwi_request_device_sync(self.instance, self.adapter)
    if self.device == nil then
      error("Unable to create a wgpu device: " .. ffi.string(wgpu.surface.kiwi_surface_last_error()))
    end
    self.queue = assert_handle(api.wgpuDeviceGetQueue(self.device), "wgpuDeviceGetQueue")
    self:configure_surface()
  end, debug.traceback)
  if not ok then
    self:destroy()
    error(result)
  end
  return self
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
