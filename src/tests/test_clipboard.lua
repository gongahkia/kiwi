local Assert = require("tests.assert")
local Base64 = require("kiwi.terminal.base64")
local Clipboard = require("kiwi.input.clipboard")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")

local function write_row(state, row, codepoints)
  state:set_cursor(0, row)
  for _, codepoint in ipairs(codepoints) do
    state:write_codepoint(Utf8.encode(codepoint), codepoint)
  end
end

local function bridge(read_text, read_status)
  return {
    clipboard_read = function(self, limit)
      self.read_limit = limit
      return read_text, read_status
    end,
    clipboard_write = function(self, text)
      self.written = text
      return true
    end,
  }
end

return {
  clipboard_copy_reconstructs_normalized_unicode_selection_text = function()
    local state = State.new(5, 2)
    write_row(state, 0, { 0x68, 0x65, 0x6c, 0x6c, 0x6f })
    write_row(state, 1, { 0x4e2d, 0x65, 0x301, 0x5a })
    state:set_selection(0, 1, 1, 3)
    local platform = bridge()
    local clipboard = Clipboard.new(platform)
    Assert.truthy(clipboard:copy(state))
    Assert.equal(platform.written, "ello\n中é")
  end,

  clipboard_copy_skips_wide_continuations_and_joins_soft_wrapped_rows = function()
    local state = State.new(4, 2)
    write_row(state, 0, { 0x41, 0x4e2d, 0x42 })
    write_row(state, 1, { 0x43, 0x44 })
    state.primary.rows[0].wrapped = true
    state:set_selection(0, 0, 1, 2)
    local platform = bridge()
    Assert.truthy(Clipboard.new(platform):copy(state))
    Assert.equal(platform.written, "A中BCD")
  end,

  clipboard_copy_rejects_empty_and_over_limit_selections_without_writing = function()
    local state = State.new(5, 1)
    write_row(state, 0, { 0x68, 0x65, 0x6c, 0x6c, 0x6f })
    local platform = bridge()
    local clipboard = Clipboard.new(platform, { maximum_bytes = 4 })
    local copied, status = clipboard:copy(state)
    Assert.truthy(not copied)
    Assert.equal(status, "no-selection")
    state:set_selection(0, 0, 0, 5)
    copied, status = clipboard:copy(state)
    Assert.truthy(not copied)
    Assert.equal(status, "over-limit")
    Assert.equal(platform.written, nil)
    local counters = clipboard:snapshot().counters
    Assert.equal(counters.copy_no_selection, 1)
    Assert.equal(counters.copy_over_limit, 1)
  end,

  clipboard_paste_preserves_utf8_and_bracketed_mode_framing = function()
    local platform = bridge("a\n中")
    local clipboard = Clipboard.new(platform)
    local bracketed = { modes = { bracketed_paste = true } }
    local bytes = clipboard:paste(bracketed)
    Assert.equal(bytes, "\27[200~a\n中\27[201~")
    Assert.equal(platform.read_limit, Clipboard.maximum_bytes)
    platform = bridge("a\n中")
    bytes = Clipboard.new(platform):paste({ modes = { bracketed_paste = false } })
    Assert.equal(bytes, "a\n中")
  end,

  clipboard_paste_rejects_invalid_unavailable_and_oversized_data_atomically = function()
    local clipboard = Clipboard.new(bridge("bad\0text"))
    local bytes, status = clipboard:paste({ modes = {} })
    Assert.equal(bytes, nil)
    Assert.equal(status, "invalid_utf8")
    clipboard = Clipboard.new(bridge("\255"))
    bytes, status = clipboard:paste({ modes = {} })
    Assert.equal(bytes, nil)
    Assert.equal(status, "invalid_utf8")
    clipboard = Clipboard.new(bridge(nil, "unavailable"))
    bytes, status = clipboard:paste({ modes = {} })
    Assert.equal(bytes, nil)
    Assert.equal(status, "unavailable")
    clipboard = Clipboard.new(bridge("abcde"), { maximum_bytes = 4 })
    bytes, status = clipboard:paste({ modes = {} })
    Assert.equal(bytes, nil)
    Assert.equal(status, "over_limit")
  end,
  clipboard_osc52_write_keeps_platform_and_utf8_validation_at_the_host_boundary = function()
    local platform = bridge()
    local clipboard = Clipboard.new(platform, { maximum_bytes = 4 })
    Assert.truthy(clipboard:write_osc52("ok"))
    Assert.equal(platform.written, "ok")
    local written, status = clipboard:write_osc52("hello")
    Assert.equal(written, false)
    Assert.equal(status, "over-limit")
    written, status = clipboard:write_osc52("\255")
    Assert.equal(written, false)
    Assert.equal(status, "invalid-utf8")
  end,
  clipboard_osc52_read_returns_only_a_bounded_validated_reply = function()
    local clipboard = Clipboard.new(bridge("a\n中"), { maximum_bytes = 16 })
    local reply, status = clipboard:read_osc52_reply("c", 8)
    Assert.equal(reply, "\27]52;c;" .. Base64.encode("a\n中") .. "\27\\")
    Assert.equal(status, "success")
    Assert.equal(clipboard:snapshot().counters.osc52_read_success, 1)
    reply, status = Clipboard.new(bridge("abcde"), { maximum_bytes = 16 }):read_osc52_reply("p", 4)
    Assert.equal(reply, nil)
    Assert.equal(status, "over-limit")
    reply, status = Clipboard.new(bridge("\255"), { maximum_bytes = 16 }):read_osc52_reply("s", 4)
    Assert.equal(reply, nil)
    Assert.equal(status, "invalid-utf8")
    reply, status = Clipboard.new(bridge(nil, "unavailable"), { maximum_bytes = 16 }):read_osc52_reply("c", 4)
    Assert.equal(reply, nil)
    Assert.equal(status, "unavailable")
  end,
}
