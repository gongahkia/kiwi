local Window = require("kiwi.platform.gtk_window")

local window
local ok, message = xpcall(function()
  window = Window.new(320, 200, "Kiwi GTK input smoke")
  local preedit
  local committed
  local correlated
  window:set_input_handlers(function(codepoints, event)
    correlated = { codepoints = codepoints, event = event }
  end, function(key, action)
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
end, debug.traceback)

if window then window:destroy() end
assert(ok, message)
print("GTK text-input callback smoke passed.")
