function love.conf(settings)
  settings.identity = "stanczyk"
  settings.version = "11.5"
  settings.window.title = "Stanczyk"
  settings.window.width = 1280
  settings.window.height = 720
  settings.window.resizable = true
  settings.window.highdpi = true
  settings.window.usedpiscale = true
  if os.getenv("STANCZYK_SCREENSHOT_SCENARIO") then
    settings.window.width = 960
    settings.window.height = 640
    settings.window.resizable = false
    settings.window.highdpi = false
    settings.window.usedpiscale = false
  end
end
