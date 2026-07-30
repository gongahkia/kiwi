local assertions = require("support.assertions")
local Metadata = require("recording.metadata")

return {
  {
    name = "recording metadata encodes canonical sorted JSON",
    run = function()
      local metadata = {
        created_by = "stanczyk/test",
        environment_allowlist = { LANG = "C", TERM = "xterm-256color" },
        format = "stanczyk-recording",
        initial_columns = 80,
        initial_rows = 24,
        notes = Metadata.null,
        profile = "stanczyk-basic-v1",
      }
      local expected =
        '{"created_by":"stanczyk/test","environment_allowlist":{"LANG":"C","TERM":"xterm-256color"},"format":"stanczyk-recording","initial_columns":80,"initial_rows":24,"notes":null,"profile":"stanczyk-basic-v1"}'
      assertions.equal(expected, assert(Metadata.encode(metadata)))
      assertions.equal(expected, assert(Metadata.encode(metadata)))
    end,
  },
  {
    name = "recording metadata escapes controls and preserves UTF-8",
    run = function()
      local encoded = assert(Metadata.encode({ message = 'é\n\8\31\\"' }))
      assertions.equal('{"message":"é\\n\\b\\u001f\\\\\\""}', encoded)
    end,
  },
  {
    name = "recording metadata rejects unsupported and ambiguous values",
    run = function()
      local value, error_value = Metadata.encode({ value = 1.5 })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      value, error_value = Metadata.encode({ "array" })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      value, error_value = Metadata.encode({ invalid = "\195" })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      local cyclic = {}
      cyclic.self = cyclic
      value, error_value = Metadata.encode(cyclic)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
}
