package.path = table.concat({
  "src/?.lua",
  "src/?/init.lua",
  package.path,
}, ";")

local Standalone = require("app.standalone")
local ScreenshotCapture = require("app.screenshot_capture")

local standalone
local screenshot_capture

local function screenshot_environment()
  return "love-" .. love._version
end

function love.load()
  local scenario = os.getenv("STANCZYK_SCREENSHOT_SCENARIO")
  if scenario then
    screenshot_capture = assert(ScreenshotCapture.new(love.graphics, love.filesystem, {
      environment = screenshot_environment(),
      output_dir = os.getenv("STANCZYK_SCREENSHOT_DIR") or "screenshots/manual",
      scenario = scenario,
    }))
    local paths = screenshot_capture:paths()
    print("screenshot output: " .. love.filesystem.getSaveDirectory() .. "/" .. paths.png)
    return
  end
  standalone = assert(Standalone.from_love(love.graphics, { padding = 32 }))
end

function love.resize()
  if screenshot_capture then
    return
  end
  assert(standalone:resize_window())
end

function love.update(seconds)
  if screenshot_capture then
    local status = screenshot_capture:status()
    if status.failure then
      error(status.failure)
    end
    if status.completed then
      love.event.quit()
    end
    return
  end
  assert(standalone:update(seconds))
end

function love.draw()
  if screenshot_capture then
    assert(screenshot_capture:draw())
    return
  end
  assert(standalone:draw())
end

function love.quit()
  if screenshot_capture then
    return
  end
  assert(standalone:stop())
end
