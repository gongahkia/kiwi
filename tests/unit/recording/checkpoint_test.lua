local assertions = require("support.assertions")
local Checkpoint = require("recording.checkpoint")
local Event = require("runtime.event")
local Format = require("recording.format")
local Frames = require("recording.frames")
local Terminal = require("terminal.terminal")

local function terminal(options)
  return assert(Terminal.new(options or {}))
end

local function digest(value)
  return assert(value:digest())
end

local function feed(value, bytes)
  assert(value:feed_output(bytes))
end

local function replace_byte(bytes, offset, value)
  return bytes:sub(1, offset - 1) .. string.char(value) .. bytes:sub(offset + 1)
end

local function checkpoint(value, limits)
  return assert(Checkpoint.decode(assert(Checkpoint.encode(value, limits)), limits))
end

return {
  {
    name = "checkpoint schema round trips an empty default terminal",
    run = function()
      local original = terminal()
      local payload = assert(Checkpoint.encode(original))
      assertions.equal("\1\0", payload:sub(1, 2))
      local restored = assert(Checkpoint.decode(payload))
      assertions.equal(digest(original), digest(restored))
    end,
  },
  {
    name = "checkpoint schema round trips populated terminal state canonically",
    run = function()
      local original = terminal({ columns = 8, rows = 3, scrollback_limit = 6 })
      feed(original, "\27[31mred\27[0m\nline-2\nline-3\nline-4\27[?7l\27[?25l\27" .. "7")
      original.margins.bottom = 2
      original.primary_screen.rows[1].wrapped = true
      original.alternate_screen.rows[2].wrapped = true
      original.tab_stops[2] = true
      local first = assert(Checkpoint.encode(original))
      local restored = assert(Checkpoint.decode(first))
      local second = assert(Checkpoint.encode(restored))
      assertions.equal(digest(original), digest(restored))
      assertions.equal(first, second)
    end,
  },
  {
    name = "checkpoint schema preserves primary alternate and active screens",
    run = function()
      local original = terminal({ columns = 8, rows = 3, scrollback_limit = 2 })
      feed(original, "primary")
      feed(original, "\27[?1049h")
      feed(original, "alternate")
      local restored = checkpoint(original)
      assertions.equal("alternate", restored.active_buffer)
      assertions.equal(digest(original), digest(restored))
      feed(original, "\27[?1049l")
      feed(restored, "\27[?1049l")
      assertions.equal(digest(original), digest(restored))
    end,
  },
  {
    name = "checkpoint schema resumes partial controls and incomplete UTF-8",
    run = function()
      local control_direct = terminal({ columns = 8, rows = 3, scrollback_limit = 0 })
      feed(control_direct, "\27[31")
      local control_restored = checkpoint(control_direct)
      feed(control_direct, "mX")
      feed(control_restored, "mX")
      assertions.equal(digest(control_direct), digest(control_restored))

      local utf8_direct = terminal({ columns = 8, rows = 3, scrollback_limit = 0 })
      feed(utf8_direct, "\195")
      local utf8_restored = checkpoint(utf8_direct)
      feed(utf8_direct, "\169")
      feed(utf8_restored, "\169")
      assertions.equal(digest(utf8_direct), digest(utf8_restored))

      local osc_direct = terminal({ columns = 8, rows = 3, scrollback_limit = 0 })
      feed(osc_direct, "\27]0;title")
      local osc_restored = checkpoint(osc_direct)
      feed(osc_direct, "\7")
      feed(osc_restored, "\7")
      assertions.equal(digest(osc_direct), digest(osc_restored))
    end,
  },
  {
    name = "checkpoint restoration is seek-equivalent to replay from the beginning",
    run = function()
      local direct = terminal({ columns = 10, rows = 3, scrollback_limit = 4 })
      local prefix = "one\n\27[32mtwo\27[0m\27[?1049halt\27[?1049l\27["
      local suffix = "31mthree\27[0m\n\195\169"
      feed(direct, prefix)
      local restored = checkpoint(direct)
      feed(direct, suffix)
      feed(restored, suffix)
      assertions.equal(digest(direct), digest(restored))
    end,
  },
  {
    name = "checkpoint schema rejects every truncated prefix cleanly",
    run = function()
      local original = terminal({ columns = 3, rows = 2, scrollback_limit = 0 })
      feed(original, "xy")
      local payload = assert(Checkpoint.encode(original))
      for length = 0, #payload - 1 do
        local value, error_value = Checkpoint.decode(payload:sub(1, length))
        assertions.falsy(value, "accepted truncated checkpoint length " .. length)
        assertions.equal("recording_corrupt", error_value.kind)
      end
    end,
  },
  {
    name = "checkpoint schema rejects versions enums and oversized allocation fields",
    run = function()
      local original = terminal({ columns = 2, rows = 1, scrollback_limit = 0 })
      local payload = assert(Checkpoint.encode(original))
      local value, error_value = Checkpoint.decode(replace_byte(payload, 1, 2))
      assertions.falsy(value)
      assertions.equal("recording_unsupported_version", error_value.kind)

      value, error_value = Checkpoint.decode(replace_byte(payload, 3, 2))
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      value, error_value = Checkpoint.decode(replace_byte(payload, 12, 2))
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      local oversized_dimensions = replace_byte(payload, 4, 0x03)
      oversized_dimensions = replace_byte(oversized_dimensions, 5, 0xE8)
      oversized_dimensions = replace_byte(oversized_dimensions, 6, 0x03)
      oversized_dimensions = replace_byte(oversized_dimensions, 7, 0xE8)
      value, error_value = Checkpoint.decode(oversized_dimensions)
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      value, error_value = Checkpoint.decode(payload, { max_checkpoint_bytes = #payload - 1 })
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      value, error_value = Checkpoint.decode(replace_byte(payload, 19, 0xFF))
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      local oversized_cell = replace_byte(payload, 49, 0xFF)
      oversized_cell = replace_byte(oversized_cell, 50, 0xFF)
      value, error_value = Checkpoint.decode(oversized_cell)
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      value, error_value = Checkpoint.decode(replace_byte(payload, 48, 1))
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      value, error_value = Checkpoint.decode(payload .. "\0")
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
    end,
  },
  {
    name = "checkpoint mutations produce only valid different states or typed errors",
    run = function()
      local original = terminal({ columns = 2, rows = 1, scrollback_limit = 0 })
      local payload = assert(Checkpoint.encode(original))
      local original_digest = digest(original)
      for _, mutation in ipairs({ { 3, 9 }, { 12, 1 }, { 13, 0 }, { 14, 0 }, { 19, 2 } }) do
        local value, error_value =
          Checkpoint.decode(replace_byte(payload, mutation[1], mutation[2]))
        if value then
          assertions.falsy(digest(value) == original_digest, "mutation decoded as unchanged state")
        else
          assertions.truthy(
            error_value.kind == "recording_corrupt"
              or error_value.kind == "recording_unsupported_version"
          )
        end
      end
    end,
  },
  {
    name = "recordings without checkpoint frames retain existing event decoding",
    run = function()
      local output = assert(Frames.from_event(assert(Event.output("plain", 1))))
      local mark = assert(Frames.from_event(assert(Event.mark("before", {}, 2))))
      local bytes = assert(Format.encode_frame(output)) .. assert(Format.encode_frame(mark))
      local first, offset = assert(Format.decode_frame(bytes))
      local second = assert(Format.decode_frame(bytes, offset))
      assertions.equal("output", assert(Frames.to_event(first)).kind)
      assertions.equal("mark", assert(Frames.to_event(second)).kind)
    end,
  },
  {
    name = "checkpoint frames use the recording frame checksum",
    run = function()
      local original = terminal({ columns = 3, rows = 2, scrollback_limit = 0 })
      feed(original, "abc")
      local frame = assert(Frames.checkpoint(original, 7))
      local bytes = assert(Format.encode_frame(frame))
      local decoded = assert(Format.decode_frame(bytes))
      local restored = assert(Frames.restore_checkpoint(decoded))
      assertions.equal(digest(original), digest(restored))

      local corrupted = replace_byte(
        bytes,
        Format.frame_header_size + 3,
        (bytes:byte(Format.frame_header_size + 3) + 1) % 256
      )
      local value, error_value = Format.decode_frame(corrupted)
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
    end,
  },
}
