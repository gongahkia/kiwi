local Context = require("kiwi.gpu.context")
local HostEffects = require("kiwi.app.host_effects")
local Window = require("kiwi.platform.window")
local GLFWHost = require("kiwi.app.glfw_host")

local function require_result(result, message)
  assert(result, message)
end

local window
local context
local second_window
local second_context
local standalone_window
local standalone_context
local ok, message = xpcall(function()
  window = Window.new(320, 240, "Kiwi Cocoa smoke")
  context = Context.new(GLFWHost, window)
  second_window = Window.new(240, 180, "Kiwi Cocoa second-window smoke")
  second_context = Context.new(GLFWHost, second_window)
  require_result(Window.live_count() == 2, "Cocoa multi-window smoke did not retain both GLFW windows")
  local tabs_ok, tabs_message = window:cocoa_window_tabs_round_trip(second_window)
  require_result(tabs_ok, "Cocoa native window-tab smoke failed: " .. tostring(tabs_message))
  local selected_next, selected_next_message = window:cocoa_select_next_window_tab()
  require_result(selected_next, "Cocoa native window-tab selection smoke failed: " .. tostring(selected_next_message))
  second_context:destroy()
  second_context = nil
  second_window:destroy()
  second_window = nil
  require_result(Window.live_count() == 1, "Cocoa native-tab smoke terminated GLFW while the primary window remained live")
  standalone_window = GLFWHost.new(nil, "Kiwi Cocoa standalone-window smoke", { host_tab = false })
  standalone_context = Context.new(GLFWHost, standalone_window)
  require_result(Window.live_count() == 2, "Cocoa standalone-window smoke did not retain both GLFW windows")
  local standalone_ok, standalone_message = standalone_window:cocoa_window_is_standalone()
  require_result(standalone_ok, "Cocoa standalone-window smoke failed: " .. tostring(standalone_message))

  local clipboard_ok, clipboard_message = window:cocoa_private_clipboard_round_trip("kiwi-cocoa-private-pasteboard-✓")
  require_result(clipboard_ok, "Cocoa private pasteboard smoke failed: " .. tostring(clipboard_message))
  local accessibility_ok, accessibility_message = window:cocoa_accessibility_round_trip()
  require_result(accessibility_ok, "Cocoa accessibility smoke failed: " .. tostring(accessibility_message))
  local text_input_ok, text_input_message = window:cocoa_text_input_round_trip()
  require_result(text_input_ok, "Cocoa text-input smoke failed: " .. tostring(text_input_message))
  local key_variants = window:cocoa_key_variants(0, string.byte("A"))
  require_result(key_variants and key_variants.layout_key >= 0x20 and key_variants.shifted_key >= 0x20 and key_variants.base_key == string.byte("a"), "Cocoa current-layout key-variant bridge did not produce a Kitty flag-4 tuple")
local host_effects = HostEffects.new({
  notify_on_command_finish = "never",
  notify_on_command_finish_after = 5,
  osc9_notifications = "off",
  osc9_progress = "system",
}, GLFWHost, window)
  local progress_handled, progress_status = host_effects:consume({ kind = "progress_changed", value = { progress = 73, state = 1 } })
  require_result(progress_handled and progress_status == "submitted", "Cocoa terminal-progress host policy did not submit the native request")
  local progress_smoke, progress_smoke_message = window:cocoa_progress_round_trip()
  require_result(progress_smoke, "Cocoa terminal-progress smoke failed: " .. tostring(progress_smoke_message))
  local directory_smoke, directory_smoke_message = window:cocoa_directory_round_trip()
  require_result(directory_smoke, "Cocoa proxy URL smoke failed: " .. tostring(directory_smoke_message))
  local menu_actions = {}
  local menu_enabled, menu_message = window:enable_cocoa_menu(function(action)
    menu_actions[#menu_actions + 1] = action
  end)
  require_result(menu_enabled, "Cocoa menu callback bridge could not be enabled: " .. tostring(menu_message))
  local menu_smoke, menu_smoke_message = window:cocoa_menu_invoke_smoke("new-tab")
  require_result(menu_smoke, "Cocoa menu callback bridge failed: " .. tostring(menu_smoke_message))
  require_result(#menu_actions == 1 and menu_actions[1] == "new-tab", "Cocoa menu callback bridge did not route the logical action")
  local configuration_menu_smoke, configuration_menu_smoke_message = window:cocoa_menu_invoke_smoke("open-configuration")
  require_result(configuration_menu_smoke, "Cocoa Settings menu callback bridge failed: " .. tostring(configuration_menu_smoke_message))
  require_result(#menu_actions == 2 and menu_actions[2] == "open-configuration", "Cocoa Settings menu did not route the configuration action")
  local palette_actions = {}
  local palette_enabled, palette_message = window:show_cocoa_command_palette({
    { action = "reload-config", title = "Reload, safely", description = "Reload the trusted \"theme\"." },
  }, function(action)
    palette_actions[#palette_actions + 1] = action
  end)
  require_result(palette_enabled, "Cocoa command-palette callback bridge could not be enabled: " .. tostring(palette_message))
  local palette_smoke, palette_smoke_message = window:cocoa_command_palette_invoke_smoke()
  require_result(palette_smoke, "Cocoa command-palette callback bridge failed: " .. tostring(palette_smoke_message))
  require_result(#palette_actions == 1 and palette_actions[1] == "reload-config", "Cocoa command palette did not route the configured logical action")
  local marked = {}
  local committed = {}
  local enabled, enabled_message = window:enable_cocoa_text_input(function(text, selection_start, selection_end)
    marked[#marked + 1] = { selection_end = selection_end, selection_start = selection_start, text = text }
  end, function(text)
    committed[#committed + 1] = text
  end)
  require_result(enabled, "Cocoa text-input callback bridge could not be enabled: " .. tostring(enabled_message))
  require_result(window:set_cocoa_text_input_caret(12, 18, 9, 18), "Cocoa text-input caret could not be updated")
  local injected, injected_message = window:cocoa_text_input_inject_smoke()
  require_result(injected, "Cocoa text-input callback bridge failed: " .. tostring(injected_message))
  require_result(#marked == 2 and marked[1].text == "中" and marked[1].selection_start == 0 and marked[1].selection_end == 3 and marked[2].text == "", "Cocoa text-input callback bridge did not deliver marked-text lifecycle")
  require_result(#committed == 1 and committed[1] == "語", "Cocoa text-input callback bridge did not deliver committed UTF-8")

  local initial_width, initial_height = window:drawable_size()
  window:set_size(640, 480)
  local resized_width, resized_height = initial_width, initial_height
  for _ = 1, 100 do
    window:wait_events(0.01)
    resized_width, resized_height = window:drawable_size()
    if window.resized and (resized_width ~= initial_width or resized_height ~= initial_height) then break end
  end
  require_result(window.resized and (resized_width ~= initial_width or resized_height ~= initial_height), "Cocoa resize smoke did not receive a changed framebuffer size")
  require_result(context:configure_surface(), "Cocoa resize smoke could not configure the resized Metal surface")
  require_result(context.width == resized_width and context.height == resized_height, "Cocoa resize smoke configured a stale drawable size")
  require_result(standalone_context:configure_surface(), "Cocoa standalone-window smoke could not configure the second Metal surface")
  standalone_context:destroy()
  standalone_context = nil
  standalone_window:destroy()
  standalone_window = nil
  require_result(Window.live_count() == 1, "Cocoa standalone-window smoke terminated GLFW while the primary window remained live")
  require_result(context:configure_surface(), "Cocoa primary surface stopped working after the second window closed")

  print(string.format("Cocoa native smoke passed: private-pasteboard, NSAccessibility projection, NSTextInputClient marked/commit/candidate geometry, current-layout Kitty key variants, local proxy URL, configured command-palette callback, resize=%dx%d, AppKit tab selection, and a standalone Metal window", resized_width, resized_height))
end, debug.traceback)

if second_context then second_context:destroy() end
if second_window then second_window:destroy() end
if standalone_context then standalone_context:destroy() end
if standalone_window then standalone_window:destroy() end
if context then context:destroy() end
if window then window:destroy() end
assert(ok, message)
