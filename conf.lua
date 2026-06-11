function love.conf(t)
  t.identity = "tikrit"
  t.version = "11.5"
  t.console = false

  local validate = false
  for _, item in ipairs(arg or {}) do
    if item == "--smoke" or item == "--validate" or item == "--validate-fast" or item == "--validate-deep" or item:match("^%-%-validate=") then
      validate = true
      break
    end
  end

  if validate then
    t.modules.window = false
    t.modules.graphics = false
    t.modules.audio = false
    t.modules.sound = false
    return
  end

  t.window.title = "Tikrit"
  t.window.width = 960
  t.window.height = 540
  t.window.minwidth = 800
  t.window.minheight = 450
  t.window.resizable = true
  t.window.vsync = 1
end
