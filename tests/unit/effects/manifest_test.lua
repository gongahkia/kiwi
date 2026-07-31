local assertions = require("support.assertions")
local Manifest = require("effects.manifest")

local function manifest()
  return {
    api_version = 1,
    capabilities = { "terminal_events", "cell_observation" },
    determinism = "deterministic",
    id = "test.manifest",
    parameters = {
      enabled = { default = true, type = "boolean" },
      intensity = { default = 0.35, max = 1, min = 0, type = "number" },
      mode = { default = "soft", type = "enum", values = { "soft", "hard" } },
      name = { default = "clean", max_length = 16, type = "string" },
      passes = { default = 2, max = 4, min = 0, type = "integer" },
    },
    version = "0.1.0",
  }
end

return {
  {
    name = "effect manifests normalise every v1 schema type independently",
    run = function()
      local source = manifest()
      local value = assert(Manifest.normalise(source))
      assertions.equal(1, value.api_version)
      assertions.equal("cell_observation", value.capabilities[2])
      assertions.equal(true, value.parameters.enabled.default)
      assertions.equal(0.35, value.parameters.intensity.default)
      assertions.equal("soft", value.parameters.mode.values[1])
      assertions.equal("clean", value.parameters.name.default)
      assertions.equal(2, value.parameters.passes.default)
      source.capabilities[1] = "draw_after"
      source.parameters.mode.values[1] = "changed"
      assertions.equal("terminal_events", value.capabilities[1])
      assertions.equal("soft", value.parameters.mode.values[1])
      local copy = Manifest.copy(value)
      copy.parameters.name.default = "changed"
      assertions.equal("clean", value.parameters.name.default)
    end,
  },
  {
    name = "effect manifests reject unsupported versions capabilities and fields",
    run = function()
      local value = manifest()
      value.api_version = 2
      local result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
      value = manifest()
      value.capabilities = { "terminal_events", "terminal_events" }
      result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
      value = manifest()
      value.capabilities = { "unknown" }
      result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
      value = manifest()
      value.extra = true
      result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
    end,
  },
  {
    name = "effect manifests reject invalid serialisable parameter schemas",
    run = function()
      local value = manifest()
      value.parameters.intensity.default = 2
      local result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
      value = manifest()
      value.parameters.passes.default = 2.5
      result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
      value = manifest()
      value.parameters.mode.values = { "soft", "soft" }
      result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
      value = manifest()
      value.parameters.name.max_length = 2
      result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
    end,
  },
  {
    name = "effect manifests gate seeded random access by determinism class",
    run = function()
      local value = manifest()
      value.capabilities[3] = "deterministic_random"
      assertions.truthy(Manifest.normalise(value))
      value.determinism = "static"
      local result, error_value = Manifest.normalise(value)
      assertions.falsy(result)
      assertions.equal("effect_load_error", error_value.kind)
    end,
  },
}
