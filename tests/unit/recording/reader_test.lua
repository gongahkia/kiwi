local assertions = require("support.assertions")
local RecordingReader = require("recording.reader")

return {
  {
    name = "recording reader bootstrap never reads source directly",
    run = function()
      local reader = assert(RecordingReader.new({}))
      local frame, error_value = reader:read_next()
      assertions.falsy(frame)
      assertions.equal("recording_io_error", error_value.kind)
    end,
  },
  {
    name = "recording reader rejects non-table source",
    run = function()
      local reader, error_value = RecordingReader.new("recording.strec")
      assertions.falsy(reader)
      assertions.equal("config_error", error_value.kind)
    end,
  },
}
