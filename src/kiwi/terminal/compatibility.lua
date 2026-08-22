local Json = require("kiwi.bench.json")

local Compatibility = {
  schema_version = 1,
  version = "1.0",
  next_version = "1.1",
  supported = {
    "c0-controls",
    "esc-controls-and-character-sets",
    "cursor-erase-edit-and-margins",
    "primary-alternate-screens-and-primary-reflow",
    "sgr-16-256-rgb-state",
    "osc-title-hyperlink-palette-shell-metadata",
    "default-denied-bounded-osc52-write",
    "device-status-attributes-and-read-only-geometry",
    "mouse-focus-and-bracketed-paste",
    "kitty-keyboard-flags-1-2-8-16",
    "bounded-kitty-png-apng-gif",
  },
  partial = {
    "xterm-private-mode-surface",
    "terminfo-256-colour-and-direct-rgb-contract",
    "kitty-keyboard-flag-4-macos",
    "macos-nsaccessibility-active-pane-projection",
  },
  deferred = {
    "bidi-and-unicode-line-breaking",
    "touch-gesture-and-locator-mouse",
    "sixel-video-and-broader-kitty-graphics",
    "exhaustive-dec-private-modes",
    "osc52-read-query-clear-and-synchronization",
  },
  next = {
    "corpus-driven-xterm-reset-tab-private-mode-and-query-behavior",
    "modern-input-and-osc-extensions-only-with-host-policy-tests",
  },
}

local function copy_list(source)
  local copy = {}
  for index, value in ipairs(source) do copy[index] = value end
  return copy
end

function Compatibility.snapshot()
  return {
    deferred = copy_list(Compatibility.deferred),
    next = copy_list(Compatibility.next),
    next_version = Compatibility.next_version,
    partial = copy_list(Compatibility.partial),
    schema_version = Compatibility.schema_version,
    supported = copy_list(Compatibility.supported),
    version = Compatibility.version,
  }
end

function Compatibility.encode()
  return Json.encode(Compatibility.snapshot())
end

if ... ~= "kiwi.terminal.compatibility" then io.stdout:write(Compatibility.encode(), "\n") end

return Compatibility
