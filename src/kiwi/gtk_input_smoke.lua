local Window = require("kiwi.platform.gtk_window")
local glfw = require("kiwi.ffi.glfw").constants
local Keyboard = require("kiwi.input.keyboard")

local window
local ok, message = xpcall(function()
  window = Window.new(320, 200, "Kiwi GTK input smoke")
  local preedit
  local committed
  local correlated
  local variants
  local alternate_key_sequence
  window:set_input_handlers(function(codepoints, event)
    correlated = { codepoints = codepoints, event = event }
  end, function(key, action, modifiers, key_variants)
    if action == glfw.press and key_variants.base_key == string.byte("a") then
      variants = key_variants
      local encoded = Keyboard.key(key, action, modifiers, { keyboard_flags = 5 }, glfw, key_variants)
      alternate_key_sequence = encoded and encoded.bytes
    end
    if key == string.byte("a") and action == 1 then
      return { defer_text = true, handled = true }
    end
  end)
  assert(window:enable_text_input(function(text, cursor_begin, cursor_end)
    preedit = { cursor_begin = cursor_begin, cursor_end = cursor_end, text = text }
  end, function(text)
    committed = text
  end))
  assert(window:set_text_input_caret(12, 18, 9, 18))
  local injected, reason = window:text_input_inject_smoke()
  assert(injected, "GTK text-input smoke injection failed: " .. tostring(reason))
  assert(preedit and preedit.text == "é" and preedit.cursor_begin == 3 and preedit.cursor_end == 3,
    "GTK text-input preedit did not preserve UTF-8 byte offsets")
  assert(committed == "✓", "GTK text-input commit did not preserve Unicode text")
  injected, reason = window:key_text_inject_smoke()
  assert(injected, "GTK key/text smoke injection failed: " .. tostring(reason))
  assert(correlated and correlated.event.key == string.byte("a") and correlated.codepoints[1] == string.byte("a"),
    "GTK key/text correlation did not retain the deferred key and committed text")
  assert(window.keyboard_supported_flags == 0x1f,
    "GTK key capability probe did not qualify Kitty alternate-key reporting")
  injected, reason = window:key_variants_inject_smoke()
  assert(injected, "GTK key-variant smoke injection failed: " .. tostring(reason))
  assert(variants and variants.layout_key >= 0x20 and variants.shifted_key >= 0x20 and variants.base_key == string.byte("a"),
    "GTK key-variant bridge did not produce a Kitty flag-4 tuple")
  local expected_alternate_key_sequence = string.format("\27[%d:%d:%d;6u",
    variants.layout_key, variants.shifted_key, variants.base_key)
  assert(alternate_key_sequence == expected_alternate_key_sequence,
    "GTK key-variant bridge did not encode the active-layout Kitty flag-4 tuple")
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
print("GTK text-input and alternate-key callback smoke passed.")
