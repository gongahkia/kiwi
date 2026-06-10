local Level = require("level")
local U = require("utils")

local floor = math.floor
local max = math.max
local min = math.min
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin

local UI = {}

local function terrainColor(cell)
  if cell.gateLocked then
    return 0.78, 0.52, 0.12
  elseif cell.ladder then
    return 0.96, 0.7, 0.24
  elseif cell.stair then
    return 0.78, 0.48, 0.18
  elseif cell.terrain == "water" then
    return 0.14, 0.32, 0.4
  elseif cell.terrain == "moss" then
    return 0.2, 0.42, 0.24
  elseif cell.terrain == "rubble" then
    return 0.42, 0.35, 0.27
  elseif cell.terrain == "grate" or cell.terrain == "catwalk" then
    return 0.34, 0.34, 0.32
  elseif cell.terrain == "slag" then
    return 0.6, 0.22, 0.08
  elseif cell.terrain == "glass" then
    return 0.42, 0.52, 0.58
  elseif cell.terrain == "dust" then
    return 0.42, 0.38, 0.28
  end

  local floorZ = cell.floor
  if floorZ < -0.45 then
    return 0.18, 0.27, 0.33
  elseif floorZ < 0.35 then
    return 0.22, 0.20, 0.16
  elseif floorZ < 1.3 then
    return 0.28, 0.24, 0.18
  end

  return 0.33, 0.30, 0.22
end

local function drawMinimap(game, width, height)
  if not game.showMap then
    return
  end

  local level = game.level
  local size = min(width * 0.3 / level.width, height * 0.36 / level.height, 7)
  local mapWidth = level.width * size
  local mapHeight = level.height * size
  local originX = width - mapWidth - 18
  local originY = 18

  love.graphics.setColor(0, 0, 0, 0.46)
  love.graphics.rectangle("fill", originX - 7, originY - 7, mapWidth + 14, mapHeight + 14, 4, 4)

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]

      if cell.solid then
        love.graphics.setColor(0.08, 0.075, 0.067, 0.9)
      else
        local red, green, blue = terrainColor(cell)
        love.graphics.setColor(red, green, blue, 0.82)
      end

      love.graphics.rectangle("fill", originX + (x - 1) * size, originY + (y - 1) * size, size, size)
    end
  end

  for _, objective in ipairs(level.objectives) do
    if not objective.cell.objective.collected then
      love.graphics.setColor(0.4, 0.95, 1, 0.95)
      love.graphics.rectangle("fill", originX + (objective.x - 1) * size, originY + (objective.y - 1) * size, max(2, size), max(2, size))
    end
  end

  for _, refill in ipairs(level.refills) do
    if not refill.cell.refillUsed then
      love.graphics.setColor(1, 0.6, 0.16, 0.9)
      love.graphics.circle("fill", originX + refill.x * size - size, originY + refill.y * size - size, max(1.8, size * 0.45))
    end
  end

  local player = game.player
  local enemy = game.enemy
  local px = originX + player.x * size - size
  local py = originY + player.y * size - size
  local ex = originX + enemy.x * size - size
  local ey = originY + enemy.y * size - size

  love.graphics.setColor(1, 0.78, 0.3, 0.95)
  love.graphics.circle("fill", px, py, max(2.5, size * 0.58))
  love.graphics.line(px, py, px + cos(player.angle) * size * 2.4, py + sin(player.angle) * size * 2.4)

  love.graphics.setColor(0.9, 0.08, 0.05, 0.95)
  love.graphics.circle("fill", ex, ey, max(2.5, size * 0.58))

  love.graphics.setColor(0.9, 0.08, 0.05, 0.22)
  for i = 1, #enemy.path - 1 do
    local a = enemy.path[i]
    local b = enemy.path[i + 1]
    love.graphics.line(originX + a.x * size - size, originY + a.y * size - size, originX + b.x * size - size, originY + b.y * size - size)
  end
end

local function drawHud(game, width, height)
  local player = game.player
  local enemy = game.enemy
  local dx, dy = enemy.x - player.x, enemy.y - player.y
  local z = (enemy.floorZ or 0) - (player.floorZ or 0)
  local distance = sqrt(dx * dx + dy * dy + z * z * 0.35)
  local danger = U.clamp(1 - distance / 10, 0, 1)
  local cell = Level.cellAtWorld(game.level, player.x, player.y) or {}
  local traversal = Level.terrainLabels[cell.terrain] or "STONE"
  local zone = string.upper(cell.zone or "UNKNOWN")

  if cell.ladder or player.climbing then
    traversal = player.climbing and "CLIMBING" or "LADDER"
  elseif cell.stair then
    traversal = "STAIRS"
  end

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0, 0, 0, 0.42)
  love.graphics.rectangle("fill", 18, 18, 326, 202, 4, 4)

  love.graphics.setColor(0.95, 0.88, 0.68)
  love.graphics.print(string.format("TIME   %05.1f", game.survivalTime), 30, 28)
  love.graphics.setColor(0.86 + danger * 0.14, 0.78 - danger * 0.48, 0.55 - danger * 0.45)
  love.graphics.print(string.format("THREAT %02dM %-11s", floor(distance), string.upper(enemy.state or "WANDER")), 30, 55)
  love.graphics.setColor(0.78, 0.72, 0.6)
  love.graphics.print("DECK   00", 30, 82)
  love.graphics.setColor(0.82, 0.76, 0.62)
  love.graphics.print(string.format("OBJ    %d/%d", game.objectives.collected, game.objectives.total), 30, 109)
  love.graphics.setColor(0.84, 0.64, 0.36)
  love.graphics.print(string.format("TORCH  %03d%%", floor(game.torch.fuel * 100)), 30, 136)
  love.graphics.setColor(0.68, 0.64, 0.56)
  love.graphics.print(traversal .. "  " .. zone, 30, 163)
  love.graphics.setColor(0.58, 0.56, 0.5)
  love.graphics.print(string.format("SEED   %d", game.seed), 30, 190)

  if game.messageTimer > 0 then
    love.graphics.setColor(0.95, 0.86, 0.58)
    love.graphics.printf(game.message, 0, height - 78, width, "center")
  end

  if game.seedEntry.active then
    love.graphics.setColor(0, 0, 0, 0.66)
    love.graphics.rectangle("fill", 0, height * 0.42, width, 76)
    love.graphics.setColor(0.95, 0.86, 0.62)
    love.graphics.printf("SEED " .. game.seedEntry.text, 0, height * 0.45, width, "center")
    love.graphics.setColor(0.7, 0.66, 0.58)
    love.graphics.printf("ENTER TO RUN", 0, height * 0.51, width, "center")
  end

  if danger > 0 then
    love.graphics.setColor(0.65, 0.02, 0.015, danger * 0.16)
    love.graphics.rectangle("fill", 0, 0, width, height)
  end
end

local function drawEndState(game, width, height)
  if game.state ~= "caught" and game.state ~= "escaped" then
    return
  end

  local won = game.state == "escaped"

  love.graphics.setColor(0, 0, 0, 0.66)
  love.graphics.rectangle("fill", 0, 0, width, height)

  love.graphics.setFont(game.fonts.title)
  love.graphics.setColor(won and 0.36 or 0.92, won and 0.9 or 0.08, won and 0.68 or 0.045)
  love.graphics.printf(won and "EXTRACTED" or "CAUGHT", 0, height * 0.34, width, "center")

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0.95, 0.86, 0.64)
  love.graphics.printf(string.format("TIME %.1f   BEST %.1f   SEED %d", game.survivalTime, game.bestTime, game.seed), 0, height * 0.49, width, "center")
  love.graphics.setColor(0.82, 0.76, 0.66)
  love.graphics.printf("R REPLAY   N NEW RUN", 0, height * 0.58, width, "center")
end

function UI.draw(game)
  local width, height = love.graphics.getDimensions()
  drawMinimap(game, width, height)
  drawHud(game, width, height)
  drawEndState(game, width, height)
end

return UI
