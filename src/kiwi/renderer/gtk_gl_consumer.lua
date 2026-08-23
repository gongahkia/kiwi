-- GTK/OpenGL consumer for the renderer-neutral prepared-frame ABI.
--
-- Native submission copies its snapshot before queueing GtkGLArea work, so a
-- successful submit is the acknowledgement point for terminal damage.
local Invalidation = require("kiwi.renderer.invalidation")
local PreparedFrame = require("kiwi.renderer.prepared_frame")

local Consumer = {}
Consumer.__index = Consumer

function Consumer.new(window, font, model, options)
  options = options or {}
  assert(type(window) == "table" and type(window.enable_gl_area_probe) == "function" and
    type(window.submit_gl_area_snapshot) == "function", "GTK GL consumer needs a GL snapshot window")
  local enabled, reason = window:enable_gl_area_probe()
  assert(enabled, "GTK GL renderer could not be enabled: " .. tostring(reason))
  local revision = options.next_revision or 2
  assert(type(revision) == "number" and revision >= 2 and revision % 1 == 0,
    "GTK GL consumer next revision must be an integer of at least two")
  local prepared_frame = PreparedFrame.new(font, model, options)
  model:mark_all_dirty()
  local self = setmetatable({
    invalidation = Invalidation.new(),
    prepared_frame = prepared_frame,
    revision = revision,
    window = window,
  }, Consumer)
  self.invalidation:request("terminal")
  return self
end

function Consumer:destroy()
  if self.prepared_frame then
    self.prepared_frame:destroy()
    self.prepared_frame = nil
  end
end

function Consumer:invalidate(reason)
  self.invalidation:request(reason)
end

function Consumer:invalidation_snapshot()
  return self.invalidation:snapshot()
end

function Consumer:needs_render(time)
  assert(type(time) == "number", "GTK GL render time must be numeric")
  return self.invalidation:due(time)
end

function Consumer:next_render_deadline()
  return self.invalidation:next_deadline()
end

function Consumer:render(model, time, debug_dirty, debug_boundaries)
  assert(self.prepared_frame ~= nil, "GTK GL consumer has been destroyed")
  if model.modes and model.modes.synchronized_output == true then
    return false, "synchronized-output"
  end
  local plan = self.prepared_frame:prepare_model(model)
  local frame = self.prepared_frame:prepare_frame(model, time, debug_dirty, debug_boundaries, {
    surface_is_srgb = false,
  })
  local snapshot = self.prepared_frame:complete_snapshot(plan, frame)
  snapshot.revision = self.revision
  local submitted, reason = self.window:submit_gl_area_snapshot(snapshot)
  if not submitted then
    self.prepared_frame:discard_model(plan)
    return false, reason
  end
  self.prepared_frame:commit_model(plan)
  self.revision = self.revision + 1
  self.invalidation:consume_success(time)
  return true
end

return Consumer
