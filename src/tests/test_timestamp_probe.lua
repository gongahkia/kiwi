local Assert = require("tests.assert")
local Context = require("kiwi.gpu.context")
local ffi = require("ffi")

local function fake_presentation_context(options)
  options = options or {}
  local events = {}
  local empty_error = ffi.new("char[1]", 0)
  local texture = ffi.cast("WGPUTexture", 1)
  local view = ffi.cast("WGPUTextureView", 2)
  local encoder = ffi.cast("WGPUCommandEncoder", 3)
  local commands = ffi.cast("WGPUCommandBuffer", 4)
  local api = {
    wgpuCommandBufferRelease = function() events[#events + 1] = "command-buffer-release" end,
    wgpuCommandEncoderFinish = function() events[#events + 1] = "command-finish"; return commands end,
    wgpuCommandEncoderRelease = function() events[#events + 1] = "encoder-release" end,
    wgpuDeviceCreateCommandEncoder = function() events[#events + 1] = "encoder-create"; return encoder end,
    wgpuQueueSubmit = function(_, count, submitted)
      Assert.equal(count, 1)
      Assert.equal(submitted[0], commands)
      events[#events + 1] = "queue-submit"
    end,
    wgpuSurfaceGetCurrentTexture = function(_, output)
      events[#events + 1] = "surface-acquire"
      output.status = options.acquire_status or 1
      output.texture = texture
    end,
    wgpuSurfacePresent = function() events[#events + 1] = "surface-present"; return options.present_status or 1 end,
    wgpuTextureCreateView = function() events[#events + 1] = "view-create"; return view end,
    wgpuTextureRelease = function() events[#events + 1] = "texture-release" end,
    wgpuTextureViewRelease = function() events[#events + 1] = "view-release" end,
  }
  local context = setmetatable({
    device = ffi.cast("WGPUDevice", 5),
    native = {
      constants = { surface_occluded = 9, surface_success_optimal = 1, surface_success_suboptimal = 2 },
      lib = api,
      surface = { kiwi_surface_last_error = function() return empty_error end },
    },
    queue = ffi.cast("WGPUQueue", 6),
    surface = ffi.cast("WGPUSurface", 7),
    window = { minimized = false, resized = false },
  }, Context)
  return context, events
end

return {
  framebuffer_rgb_expectation_is_strictly_bounded = function()
    local expected = Context.parse_framebuffer_expected_rgb("18,171,52")
    Assert.equal(expected.red, 18)
    Assert.equal(expected.green, 171)
    Assert.equal(expected.blue, 52)
    Assert.equal(Context.parse_framebuffer_expected_rgb(nil), nil)
    Assert.truthy(not pcall(Context.parse_framebuffer_expected_rgb, "18,171"))
    Assert.truthy(not pcall(Context.parse_framebuffer_expected_rgb, "18,256,52"))
  end,
  surface_format_selection_prefers_an_srgb_target_with_a_safe_fallback = function()
    local formats = require("ffi").new("uint32_t[3]", { 0x1b, 0x1c, 0x17 })
    local format, is_srgb = Context.select_surface_format(formats, 3)
    Assert.equal(format, 0x1c)
    Assert.truthy(is_srgb)
    format, is_srgb = Context.select_surface_format(require("ffi").new("uint32_t[1]", { 0x1b }), 1)
    Assert.equal(format, 0x1b)
    Assert.equal(is_srgb, false)
  end,
  timestamp_probe_reports_unsupported_adapter_without_creating_resources = function()
    local supported, message = Context.probe_timestamp_queries({ timestamp_query_supported = false })
    Assert.equal(supported, false)
    Assert.equal(message, "adapter does not expose timestamp-query")
  end,
  wgpu_presentation_frames_have_one_explicit_acquire_abort_or_present_lifecycle = function()
    local context, events = fake_presentation_context()
    local frame = assert(context:begin_presentation_frame())
    Assert.equal(frame.backend, "wgpu")
    Assert.equal(frame.state, "acquired")
    Assert.truthy(context:abort_presentation_frame(frame))
    Assert.equal(frame.state, "aborted")
    Assert.equal(table.concat(events, ","), "surface-acquire,view-create,encoder-create,encoder-release,view-release,texture-release")
    Assert.truthy(not pcall(context.abort_presentation_frame, context, frame))

    context, events = fake_presentation_context()
    frame = assert(context:begin_presentation_frame())
    Assert.truthy(context:present_presentation_frame(frame))
    Assert.equal(frame.state, "presented")
    Assert.equal(table.concat(events, ","), "surface-acquire,view-create,encoder-create,command-finish,queue-submit,command-buffer-release,encoder-release,view-release,surface-present,texture-release")
    Assert.truthy(not pcall(context.present_presentation_frame, context, frame))
  end,
  wgpu_presentation_frame_returns_surface_failures_after_releasing_ownership = function()
    local context, events = fake_presentation_context({ present_status = 0 })
    local frame = assert(context:begin_presentation_frame())
    local presented, reason = context:present_presentation_frame(frame)
    Assert.equal(presented, nil)
    Assert.equal(reason, "surface present status 0")
    Assert.equal(frame.state, "presented")
    Assert.equal(table.concat(events, ","), "surface-acquire,view-create,encoder-create,command-finish,queue-submit,command-buffer-release,encoder-release,view-release,surface-present,texture-release")
  end,
}
