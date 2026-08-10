local Layout = require("kiwi.text.layout")

local Backend = {
  abi_version = 1,
}

local Atlas = {}
Atlas.__index = Atlas

function Atlas.new(font_system, requested)
  return setmetatable({
    font_system = assert(font_system, "text backend needs a font system"),
    layout_engine = Layout.new(font_system),
    requested = requested,
    fallback = requested ~= "atlas",
    fallback_reason = requested ~= "atlas" and "unsupported-backend" or nil,
    destroyed = false,
  }, Atlas)
end

function Atlas:layout()
  assert(not self.destroyed, "text backend is destroyed")
  return self.layout_engine
end

function Atlas:update(state)
  assert(not self.destroyed, "text backend is destroyed")
  return self.layout_engine:update(state)
end

function Atlas:descriptor()
  return {
    abi_version = Backend.abi_version,
    requested = self.requested,
    active = "atlas",
    fallback = self.fallback,
    fallback_reason = self.fallback_reason,
    capabilities = {
      semantic_input = "terminal-grid-text-damage-v1",
      terminal_layout_authority = "kiwi",
      glyph_output = "text.shaped_glyphs",
      gpu_resource = "text.alpha_atlas",
      rasterization = "grayscale-alpha-atlas",
    },
  }
end

function Atlas:destroy()
  self.destroyed = true
end

function Backend.create(font_system, options)
  options = options or {}
  assert(type(options) == "table", "text backend options must be a table")
  local requested = options.requested or "atlas"
  assert(type(requested) == "string" and #requested > 0 and #requested <= 64, "text backend selection must be a non-empty string of at most 64 bytes")
  return Atlas.new(font_system, requested)
end

function Backend.supported()
  return { "atlas" }
end

return Backend
