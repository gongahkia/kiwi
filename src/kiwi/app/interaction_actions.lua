-- Internal product-action catalogue shared by shortcuts, palettes and host adapters.
local Interaction = {}
Interaction.entries = {
  { id = 29, action = "previous-tab", kind = "workspace", title = "Previous Tab", description = "Focus the previous terminal tab." },
  { id = 30, action = "next-pane", kind = "workspace", title = "Next Pane", description = "Focus the next pane in layout order." },
  { id = 31, action = "previous-pane", kind = "workspace", title = "Previous Pane", description = "Focus the previous pane in layout order." },
  { id = 32, action = "focus-pane-left", kind = "workspace", title = "Focus Pane Left", description = "Focus the nearest pane to the left." },
  { id = 33, action = "focus-pane-right", kind = "workspace", title = "Focus Pane Right", description = "Focus the nearest pane to the right." },
  { id = 34, action = "focus-pane-up", kind = "workspace", title = "Focus Pane Above", description = "Focus the nearest pane above." },
  { id = 35, action = "focus-pane-down", kind = "workspace", title = "Focus Pane Below", description = "Focus the nearest pane below." },
  { id = 36, action = "toggle-pane-zoom", kind = "workspace", title = "Zoom Pane", description = "Toggle the active pane between full window and split layout." },
  { id = 37, action = "resize-pane-left", kind = "workspace", title = "Move Divider Left", description = "Move the nearest vertical divider left by two cells." },
  { id = 38, action = "resize-pane-right", kind = "workspace", title = "Move Divider Right", description = "Move the nearest vertical divider right by two cells." },
  { id = 39, action = "resize-pane-up", kind = "workspace", title = "Move Divider Up", description = "Move the nearest horizontal divider up by two cells." },
  { id = 40, action = "resize-pane-down", kind = "workspace", title = "Move Divider Down", description = "Move the nearest horizontal divider down by two cells." },
  { id = 41, action = "equalize-splits", kind = "workspace", title = "Equalize Splits", description = "Reset each divider in this tab to equal halves." },
  { id = 42, action = "increase-font-size", kind = "font", title = "Increase Font Size", description = "Increase the font size in this window." },
  { id = 43, action = "decrease-font-size", kind = "font", title = "Decrease Font Size", description = "Decrease the font size in this window." },
  { id = 44, action = "reset-font-size", kind = "font", title = "Reset Font Size", description = "Restore the configured font size." },
  { id = 45, action = "scroll-to-top", kind = "terminal", title = "Scroll to Top", description = "Show the oldest retained history." },
  { id = 46, action = "scroll-to-bottom", kind = "terminal", title = "Scroll to Bottom", description = "Return to the live terminal output." },
  { id = 47, action = "clear-scrollback", kind = "terminal", title = "Clear Scrollback", description = "Remove retained history while keeping the current screen." },
  { id = 48, action = "select-all", kind = "terminal", title = "Select All", description = "Select all retained text in the current screen buffer." },
  { id = 49, action = "copy", kind = "terminal", title = "Copy", description = "Copy the selected text." },
  { id = 50, action = "paste", kind = "terminal", title = "Paste", description = "Paste clipboard text into the active terminal." },
  { id = 51, action = "search", kind = "terminal", title = "Find", description = "Search retained terminal text." },
  { id = 52, action = "search-next", kind = "terminal", title = "Find Next", description = "Navigate to the next search match." },
  { id = 53, action = "search-previous", kind = "terminal", title = "Find Previous", description = "Navigate to the previous search match." },
}
Interaction.kinds = {}
for _, entry in ipairs(Interaction.entries) do Interaction.kinds[entry.action] = entry.kind end

function Interaction.font_target(action, current, configured)
  if action == "reset-font-size" then return configured end
  if action == "increase-font-size" then return math.min(256, current + 1) end
  if action == "decrease-font-size" then return math.max(1, current - 1) end
  error("unknown font action")
end

function Interaction.workspace(action, workspace, columns, rows)
  if action == "previous-tab" then return workspace:focus_relative_tab(-1) end
  if action == "next-pane" then return workspace:focus_relative_pane(1) end
  if action == "previous-pane" then return workspace:focus_relative_pane(-1) end
  if action == "toggle-pane-zoom" then return workspace:toggle_zoom() end
  if action == "equalize-splits" then return workspace:equalize_splits() end
  local direction = action:match("^focus%-pane%-(%a+)$")
  if direction then return workspace:focus_direction(direction, columns, rows) end
  direction = action:match("^resize%-pane%-(%a+)$")
  if direction then return workspace:resize_active_split(direction, 2, columns, rows) end
  return nil, "unknown workspace action"
end

function Interaction.terminal(action, state, clipboard, enqueue)
  if action == "copy" then return clipboard:copy(state) end
  if action == "paste" then
    local bytes, reason = clipboard:paste(state)
    if bytes == nil then return nil, reason end
    enqueue(bytes)
    return true
  end
  if action == "scroll-to-top" or action == "scroll-to-bottom" then
    if state.active_screen ~= state.primary then return false end
    state:scroll_history(action == "scroll-to-top" and state.scrollback:size() or -state.scrollback:size())
    return true
  end
  if action == "clear-scrollback" then return state:clear_scrollback() end
  if action == "select-all" then state:select_all(); return true end
  if action == "search" then state:search_begin("forward"); return true end
  if action == "search-next" or action == "search-previous" then
    local direction = action == "search-next" and "forward" or "backward"
    local match, status
    if state:search_view().editing then match, status = state:search_submit(direction)
    else match, status = state:search_navigate(direction) end
    if match == nil then return nil, status end
    return true
  end
  return nil, "unknown terminal action"
end

return Interaction
