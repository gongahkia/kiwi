local Event = require("runtime.event")
local Frames = require("recording.frames")
local RecordingWriter = require("recording.writer")

local SampleRecording = {}

local function sink()
  local value = { chunks = {} }

  function value:write(bytes)
    self.chunks[#self.chunks + 1] = bytes
    return true
  end

  function value:flush()
    return true
  end

  function value:close()
    return true
  end

  return value
end

local function source(bytes)
  local value = { bytes = bytes, offset = 1 }

  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + count - 1)
    local chunk = self.bytes:sub(self.offset, finish)
    self.offset = finish + 1
    return chunk
  end

  function value:close()
    return true
  end

  return value
end

function SampleRecording.new_source()
  local target = sink()
  local writer, writer_error = RecordingWriter.new(target, { format = "stanczyk-recording" })
  if not writer then
    return nil, writer_error
  end
  for _, output in ipairs({
    "\27[1;36mStanczyk\27[0m\r\n",
    "deterministic recording fixture\r\n",
    "resize policy: non-reflowing top-left preservation\r\n",
  }) do
    local event, event_error = Event.output(output, 0)
    if not event then
      return nil, event_error
    end
    local frame, frame_error = Frames.from_event(event)
    if not frame then
      return nil, frame_error
    end
    local appended, append_error = writer:append(frame)
    if not appended then
      return nil, append_error
    end
  end
  local closed, close_error = writer:close()
  if not closed then
    return nil, close_error
  end
  return source(table.concat(target.chunks))
end

return SampleRecording
