local Actor = require("actor")
local Level = require("level")
local U = require("utils")

local floor = math.floor
local ceil = math.ceil
local abs = math.abs
local min = math.min
local max = math.max
local cos = math.cos
local sin = math.sin
local tan = math.tan

local Renderer = {
  rayStep = 2,
  wallRenderDistance = 32,
  canvas = nil,
  shader = nil,
  postEnabled = true,
}

local shaderSource = [[
extern number time;
extern number fuel;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec4 px = Texel(tex, uv) * color;
  vec2 p = uv - vec2(0.5);
  number vignette = 1.0 - smoothstep(0.25, 0.78, dot(p, p) * 1.7);
  number scan = 0.94 + 0.035 * sin(screen.y * 1.7 + time * 18.0);
  number lowFuel = 0.62 + fuel * 0.38;
  px.rgb *= mix(0.7, 1.0, vignette) * scan * lowFuel;
  px.rgb = floor(px.rgb * 18.0) / 18.0;
  return px;
}
]]

function Renderer.init()
  local ok, shader = pcall(love.graphics.newShader, shaderSource)
  if ok then
    Renderer.shader = shader
  end
end

local function ensureCanvas(width, height)
  if not Renderer.canvas or Renderer.canvas:getWidth() ~= width or Renderer.canvas:getHeight() ~= height then
    Renderer.canvas = love.graphics.newCanvas(width, height)
    Renderer.canvas:setFilter("nearest", "nearest")
  end
end

local function projectWorldZ(game, worldZ, distance, height)
  local scale = height * 0.86 / max(distance, 0.035)
  return height * 0.54 - (worldZ - game.player.eyeZ) * scale
end

local function drawBackground(width, height, fuel)
  local horizon = height * 0.54
  local fuelShade = 0.72 + fuel * 0.28

  for y = 0, horizon, 6 do
    local t = y / horizon
    love.graphics.setColor((0.035 + t * 0.035) * fuelShade, (0.037 + t * 0.03) * fuelShade, (0.047 + t * 0.045) * fuelShade)
    love.graphics.rectangle("fill", 0, y, width, 7)
  end

  for y = horizon, height, 6 do
    local t = (y - horizon) / (height - horizon)
    love.graphics.setColor((0.15 - t * 0.055) * fuelShade, (0.125 - t * 0.045) * fuelShade, (0.09 - t * 0.035) * fuelShade)
    love.graphics.rectangle("fill", 0, y, width, 7)
  end

  love.graphics.setColor(0.23, 0.17, 0.11, 0.22)
  love.graphics.rectangle("fill", 0, horizon - 1, width, 2)
end

local function castRay(game, rayDirX, rayDirY)
  local level = game.level
  local player = game.player
  local mapX = floor(player.x)
  local mapY = floor(player.y)
  local previousCell = Level.cellAtCell(level, mapX, mapY)
  local deltaDistX = rayDirX == 0 and 1e30 or abs(1 / rayDirX)
  local deltaDistY = rayDirY == 0 and 1e30 or abs(1 / rayDirY)
  local stepX, stepY
  local sideDistX, sideDistY
  local side = 0
  local segments = {}

  if rayDirX < 0 then
    stepX = -1
    sideDistX = (player.x - mapX) * deltaDistX
  else
    stepX = 1
    sideDistX = (mapX + 1 - player.x) * deltaDistX
  end

  if rayDirY < 0 then
    stepY = -1
    sideDistY = (player.y - mapY) * deltaDistY
  else
    stepY = 1
    sideDistY = (mapY + 1 - player.y) * deltaDistY
  end

  for _ = 1, 180 do
    local distance

    if sideDistX < sideDistY then
      sideDistX = sideDistX + deltaDistX
      mapX = mapX + stepX
      side = 0
      distance = (mapX - player.x + (1 - stepX) / 2) / rayDirX
    else
      sideDistY = sideDistY + deltaDistY
      mapY = mapY + stepY
      side = 1
      distance = (mapY - player.y + (1 - stepY) / 2) / rayDirY
    end

    distance = max(distance, 0.01)

    if distance >= Renderer.wallRenderDistance then
      return segments, Renderer.wallRenderDistance
    end

    local nextCell = Level.cellAtCell(level, mapX, mapY)

    if Level.isBlocked(nextCell) then
      if previousCell then
        segments[#segments + 1] = {
          distance = distance,
          bottom = previousCell.floor,
          top = previousCell.ceiling,
          side = side,
          cell = previousCell,
          mapX = mapX,
          mapY = mapY,
          kind = nextCell and nextCell.kind or "outer",
          solid = true,
        }
      end

      return segments, distance
    end

    if previousCell then
      if nextCell.floor > previousCell.floor + 0.04 then
        local kind = (nextCell.ladder or previousCell.ladder) and "ladder" or (nextCell.stair and "stair" or "riser")
        segments[#segments + 1] = {
          distance = distance,
          bottom = previousCell.floor,
          top = nextCell.floor,
          side = side,
          cell = nextCell,
          mapX = mapX,
          mapY = mapY,
          kind = kind,
          solid = false,
        }
      elseif nextCell.floor < previousCell.floor - 0.04 then
        local kind = (nextCell.ladder or previousCell.ladder) and "ladder" or (nextCell.stair and "stair" or "drop")
        segments[#segments + 1] = {
          distance = distance,
          bottom = nextCell.floor,
          top = previousCell.floor,
          side = side,
          cell = previousCell,
          mapX = mapX,
          mapY = mapY,
          kind = kind,
          solid = false,
        }
      end

      if nextCell.ceiling < previousCell.ceiling - 0.04 then
        segments[#segments + 1] = {
          distance = distance,
          bottom = nextCell.ceiling,
          top = previousCell.ceiling,
          side = side,
          cell = previousCell,
          mapX = mapX,
          mapY = mapY,
          kind = "lintel",
          solid = false,
        }
      end
    end

    previousCell = nextCell
  end

  return segments, Renderer.wallRenderDistance
end

local function segmentColor(segment, shade)
  local cell = segment.cell or { floor = 0, light = 0.4 }
  local heightTint = U.clamp((cell.floor + 1.2) / 4.2, 0, 1)
  local red, green, blue

  if segment.kind == "stair" then
    red, green, blue = 0.62, 0.45, 0.27
  elseif segment.kind == "ladder" then
    red, green, blue = 0.74, 0.52, 0.25
  elseif segment.kind == "sealed gate" then
    red, green, blue = 0.64, 0.48, 0.16
  elseif segment.kind == "riser" or segment.kind == "drop" then
    if cell.terrain == "water" then
      red, green, blue = 0.18, 0.32, 0.38
    elseif cell.terrain == "moss" then
      red, green, blue = 0.25, 0.38, 0.22
    elseif cell.terrain == "slag" then
      red, green, blue = 0.62, 0.25, 0.1
    elseif cell.terrain == "rubble" then
      red, green, blue = 0.4, 0.36, 0.3
    else
      red, green, blue = 0.46, 0.42, 0.34
    end
  elseif segment.kind == "lintel" then
    red, green, blue = 0.28, 0.30, 0.34
  elseif segment.kind == "column" then
    red, green, blue = 0.42, 0.38, 0.31
  else
    red = 0.43 + heightTint * 0.12
    green = 0.39 + heightTint * 0.08
    blue = 0.33 + heightTint * 0.06
  end

  local sideShade = segment.side == 1 and 0.78 or 1
  local light = 0.5 + (cell.light or 0.45) * 0.55

  return red * shade * sideShade * light, green * shade * sideShade * light, blue * shade * sideShade * light
end

local function drawSegment(game, segment, width, height, screenX)
  local distance = max(segment.distance, 0.01)
  local yTop = projectWorldZ(game, segment.top, distance, height)
  local yBottom = projectWorldZ(game, segment.bottom, distance, height)
  local drawStart = max(0, floor(min(yTop, yBottom)))
  local drawEnd = min(height, ceil(max(yTop, yBottom)))

  if drawEnd <= drawStart then
    return
  end

  local fuel = game.torch.fuel
  local torchPulse = 0.98 + sin(game.survivalTime * 11.1) * 0.055 + sin(game.survivalTime * 23.7) * 0.025
  local baseShade = U.clamp(1 - distance / Renderer.wallRenderDistance, 0.16, 1)
  local torchShade = U.clamp(1 - distance / (8 + fuel * 8), 0, 1) * torchPulse * (0.16 + fuel * 0.34)
  local shade = U.clamp(baseShade + torchShade, 0.08, 1.18)
  local red, green, blue = segmentColor(segment, shade)

  love.graphics.setColor(red, green, blue)
  love.graphics.rectangle("fill", screenX, drawStart, Renderer.rayStep + 1, drawEnd - drawStart)

  if segment.kind == "stair" and distance < 10 then
    love.graphics.setColor(red * 1.22, green * 1.14, blue * 0.92, 0.18)
    love.graphics.rectangle("fill", screenX, drawStart, Renderer.rayStep + 1, 2)
  elseif segment.kind == "ladder" and distance < 14 then
    love.graphics.setColor(0.12, 0.07, 0.035, 0.55)
    for y = drawStart + 4, drawEnd - 2, max(4, floor(12 / distance)) do
      love.graphics.rectangle("fill", screenX, y, Renderer.rayStep + 1, 1)
    end
  elseif segment.kind == "sealed gate" and distance < 16 then
    love.graphics.setColor(1, 0.74, 0.2, 0.22)
    for y = drawStart + 4, drawEnd - 2, 9 do
      love.graphics.rectangle("fill", screenX, y, Renderer.rayStep + 1, 2)
    end
  end
end

local function surfaceColor(cell, distance, ceiling)
  local red, green, blue

  if cell.terrain == "water" then
    red, green, blue = 0.11, 0.22, 0.28
  elseif cell.terrain == "moss" then
    red, green, blue = 0.16, 0.27, 0.15
  elseif cell.terrain == "rubble" then
    red, green, blue = 0.28, 0.25, 0.20
  elseif cell.terrain == "grate" or cell.terrain == "catwalk" then
    red, green, blue = 0.23, 0.23, 0.21
  elseif cell.terrain == "slag" then
    red, green, blue = 0.36, 0.14, 0.06
  elseif cell.terrain == "glass" then
    red, green, blue = 0.25, 0.31, 0.34
  elseif cell.terrain == "dust" then
    red, green, blue = 0.28, 0.25, 0.18
  else
    red, green, blue = 0.24, 0.21, 0.16
  end

  if ceiling then
    red, green, blue = red * 0.54, green * 0.56, blue * 0.62
  end

  local shade = U.clamp(1 - distance / Renderer.wallRenderDistance, 0.12, 1)
  local light = 0.48 + (cell.light or 0.45) * 0.45

  return red * shade * light, green * shade * light, blue * shade * light
end

local function drawFloorCeiling(game, width, height)
  local player = game.player
  local level = game.level
  local currentCell = Level.cellAtWorld(level, player.x, player.y)

  if not currentCell or Level.isBlocked(currentCell) then
    return
  end

  local horizon = height * 0.54
  local projectionScale = height * 0.86
  local dirX, dirY = cos(player.angle), sin(player.angle)
  local planeScale = tan(player.fov / 2)
  local planeX, planeY = -dirY * planeScale, dirX * planeScale
  local leftRayX, leftRayY = dirX - planeX, dirY - planeY
  local rightRayX, rightRayY = dirX + planeX, dirY + planeY
  local floorZ = currentCell.floor
  local ceilingZ = currentCell.ceiling

  for y = ceil(horizon), height - 1, 2 do
    local distance = (player.eyeZ - floorZ) * projectionScale / max(y - horizon, 0.001)

    if distance < Renderer.wallRenderDistance then
      local stepX = (rightRayX - leftRayX) * distance / width
      local stepY = (rightRayY - leftRayY) * distance / width
      local worldX = player.x + leftRayX * distance
      local worldY = player.y + leftRayY * distance

      for x = 0, width - 1, Renderer.rayStep do
        local cell = Level.cellAtWorld(level, worldX, worldY)

        if cell and not Level.isBlocked(cell) then
          love.graphics.setColor(surfaceColor(cell, distance, false))
          love.graphics.rectangle("fill", x, y, Renderer.rayStep + 1, 2)
        end

        worldX = worldX + stepX * Renderer.rayStep
        worldY = worldY + stepY * Renderer.rayStep
      end
    end
  end

  for y = floor(horizon), 0, -2 do
    local distance = (ceilingZ - player.eyeZ) * projectionScale / max(horizon - y, 0.001)

    if distance < Renderer.wallRenderDistance then
      local stepX = (rightRayX - leftRayX) * distance / width
      local stepY = (rightRayY - leftRayY) * distance / width
      local worldX = player.x + leftRayX * distance
      local worldY = player.y + leftRayY * distance

      for x = 0, width - 1, Renderer.rayStep do
        local cell = Level.cellAtWorld(level, worldX, worldY)

        if cell and not Level.isBlocked(cell) then
          love.graphics.setColor(surfaceColor(cell, distance, true))
          love.graphics.rectangle("fill", x, y - 1, Renderer.rayStep + 1, 2)
        end

        worldX = worldX + stepX * Renderer.rayStep
        worldY = worldY + stepY * Renderer.rayStep
      end
    end
  end
end

local function drawRaycastWorld(game, width, height)
  local depthBuffer = {}
  local player = game.player
  local dirX, dirY = cos(player.angle), sin(player.angle)
  local planeScale = tan(player.fov / 2)
  local planeX, planeY = -dirY * planeScale, dirX * planeScale

  drawBackground(width, height, game.torch.fuel)
  drawFloorCeiling(game, width, height)

  for screenX = 0, width - 1, Renderer.rayStep do
    local cameraX = 2 * (screenX + 0.5) / width - 1
    local rayDirX = dirX + planeX * cameraX
    local rayDirY = dirY + planeY * cameraX
    local segments, solidDistance = castRay(game, rayDirX, rayDirY)

    for i = #segments, 1, -1 do
      drawSegment(game, segments[i], width, height, screenX)
    end

    for bufferX = screenX, min(screenX + Renderer.rayStep, width - 1) do
      depthBuffer[bufferX + 1] = solidDistance or Renderer.wallRenderDistance
    end
  end

  return depthBuffer
end

local function projectSprite(game, x, y, floorZ, height, width, screenHeight)
  local player = game.player
  local dx, dy = x - player.x, y - player.y
  local dirX, dirY = cos(player.angle), sin(player.angle)
  local planeScale = tan(player.fov / 2)
  local planeX, planeY = -dirY * planeScale, dirX * planeScale
  local determinant = planeX * dirY - dirX * planeY

  if abs(determinant) < 0.00001 then
    return nil
  end

  local inverseDet = 1 / determinant
  local transformX = inverseDet * (dirY * dx - dirX * dy)
  local transformY = inverseDet * (-planeY * dx + planeX * dy)

  if transformY <= 0.08 then
    return nil
  end

  local screenX = floor((width / 2) * (1 + transformX / transformY))
  local baseY = projectWorldZ(game, floorZ, transformY, screenHeight)
  local topY = projectWorldZ(game, floorZ + height, transformY, screenHeight)
  local spriteHeight = abs(floor(baseY - topY))
  local spriteWidth = max(8, floor(spriteHeight * 0.46))

  return {
    x = screenX,
    y = baseY,
    height = spriteHeight,
    width = spriteWidth,
    distance = transformY,
    left = screenX - spriteWidth / 2,
    right = screenX + spriteWidth / 2,
  }
end

local function spriteVisible(sprite, width, depthBuffer)
  if not sprite or sprite.height < 4 or sprite.right < 0 or sprite.left > width then
    return false
  end

  for x = max(0, floor(sprite.left)), min(width - 1, floor(sprite.right)), 4 do
    if sprite.distance < (depthBuffer[x + 1] or math.huge) + 0.05 then
      return true
    end
  end

  return false
end

local function drawEnemySprite(game, width, height, depthBuffer)
  local enemy = game.enemy
  local sprite = projectSprite(game, enemy.x, enemy.y, enemy.floorZ, Actor.playerHeight, width, height)

  if not spriteVisible(sprite, width, depthBuffer) then
    return
  end

  local bodyAlpha = U.clamp(1 - sprite.distance / 28, 0.32, 1)
  local bodyWidth = sprite.width
  local headY = -sprite.height * 0.58
  local headRadius = max(3, bodyWidth * 0.21)

  love.graphics.push()
  love.graphics.translate(sprite.x, sprite.y)

  love.graphics.setColor(0, 0, 0, 0.35 * bodyAlpha)
  love.graphics.ellipse("fill", 0, sprite.height * 0.03, bodyWidth * 0.36, max(2, sprite.height * 0.035))

  love.graphics.setColor(0.18, 0.02, 0.018, bodyAlpha)
  love.graphics.polygon(
    "fill",
    -bodyWidth * 0.34,
    -sprite.height * 0.04,
    -bodyWidth * 0.23,
    -sprite.height * 0.5,
    0,
    -sprite.height * 0.78,
    bodyWidth * 0.23,
    -sprite.height * 0.5,
    bodyWidth * 0.34,
    -sprite.height * 0.04
  )

  love.graphics.setColor(0.45, 0.035, 0.03, bodyAlpha)
  love.graphics.polygon(
    "fill",
    -bodyWidth * 0.16,
    -sprite.height * 0.1,
    -bodyWidth * 0.1,
    -sprite.height * 0.48,
    0,
    -sprite.height * 0.63,
    bodyWidth * 0.1,
    -sprite.height * 0.48,
    bodyWidth * 0.16,
    -sprite.height * 0.1
  )

  love.graphics.setColor(0.08, 0.008, 0.008, bodyAlpha)
  love.graphics.circle("fill", 0, headY, headRadius)

  local eyeGlow = 0.6 + game.enemy.growl * 0.4
  love.graphics.setColor(1.0, 0.76, 0.22, bodyAlpha * eyeGlow)
  love.graphics.circle("fill", -headRadius * 0.38, headY - headRadius * 0.12, max(1.5, headRadius * 0.16))
  love.graphics.circle("fill", headRadius * 0.38, headY - headRadius * 0.12, max(1.5, headRadius * 0.16))

  love.graphics.setColor(0.02, 0, 0, bodyAlpha)
  love.graphics.setLineWidth(max(1, sprite.height * 0.012))
  love.graphics.line(-headRadius * 0.55, headY + headRadius * 0.38, headRadius * 0.55, headY + headRadius * 0.38)

  love.graphics.pop()
end

local function drawPickupSprites(game, width, height, depthBuffer)
  for _, objective in ipairs(game.level.objectives) do
    if not objective.cell.objective.collected then
      local sprite = projectSprite(game, objective.x + 0.5, objective.y + 0.5, objective.cell.floor + 0.12, 0.85, width, height)
      if spriteVisible(sprite, width, depthBuffer) then
        local alpha = U.clamp(1 - sprite.distance / 24, 0.28, 0.94)
        love.graphics.push()
        love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.42)
        love.graphics.setColor(0.1, 0.22, 0.28, alpha * 0.74)
        love.graphics.rectangle("fill", -sprite.width * 0.3, -sprite.height * 0.28, sprite.width * 0.6, sprite.height * 0.58, 3, 3)
        love.graphics.setColor(0.4, 0.95, 1, alpha)
        love.graphics.rectangle("line", -sprite.width * 0.3, -sprite.height * 0.28, sprite.width * 0.6, sprite.height * 0.58, 3, 3)
        love.graphics.setColor(0.85, 1, 0.96, alpha)
        love.graphics.circle("fill", 0, -sprite.height * 0.02, max(2, sprite.width * 0.11))
        love.graphics.pop()
      end
    end
  end

  for _, refill in ipairs(game.level.refills) do
    if not refill.cell.refillUsed then
      local sprite = projectSprite(game, refill.x + 0.5, refill.y + 0.5, refill.cell.floor + 0.08, 0.55, width, height)
      if spriteVisible(sprite, width, depthBuffer) then
        local alpha = U.clamp(1 - sprite.distance / 18, 0.24, 0.84)
        love.graphics.push()
        love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.3)
        love.graphics.setColor(0.95, 0.58, 0.16, alpha)
        love.graphics.rectangle("fill", -sprite.width * 0.22, -sprite.height * 0.2, sprite.width * 0.44, sprite.height * 0.42, 2, 2)
        love.graphics.setColor(1, 0.9, 0.5, alpha * 0.7)
        love.graphics.rectangle("fill", -sprite.width * 0.12, -sprite.height * 0.28, sprite.width * 0.24, sprite.height * 0.1, 2, 2)
        love.graphics.pop()
      end
    end
  end
end

local function drawTorch(game, width, height)
  local player = game.player
  local fuel = game.torch.fuel
  local bob = sin(player.bob) * (player.moving and 7 or 2)
  local flicker = (sin(game.survivalTime * 18.5) * 3 + sin(game.survivalTime * 33.7) * 2) * (0.3 + fuel)
  local handY = height - 54 + bob
  local torchX = width * 0.57 + sin(player.bob * 0.5) * 4
  local torchY = height - 102 + bob
  local flame = U.clamp(fuel, 0.08, 1)

  love.graphics.setColor(0.10, 0.055, 0.035, 0.92)
  love.graphics.polygon("fill", width * 0.33, height, width * 0.4, handY - 18, width * 0.52, handY - 4, width * 0.51, height)

  love.graphics.setColor(0.18, 0.10, 0.065, 0.96)
  love.graphics.polygon("fill", width * 0.5, height, torchX - 30, torchY + 72, torchX + 18, torchY + 72, width * 0.68, height)

  love.graphics.setColor(0.27, 0.18, 0.10, 1)
  love.graphics.rectangle("fill", torchX - 9, torchY, 18, 104, 5, 5)

  love.graphics.setColor(0.09, 0.055, 0.032, 1)
  love.graphics.rectangle("fill", torchX - 11, torchY + 16, 22, 10, 3, 3)
  love.graphics.rectangle("fill", torchX - 11, torchY + 52, 22, 10, 3, 3)

  love.graphics.setColor(0.85, 0.55, 0.24, 1)
  love.graphics.rectangle("fill", torchX - 15, torchY - 8, 30, 18, 4, 4)

  love.graphics.setColor(1, 0.78, 0.28, 0.18 * flame)
  love.graphics.circle("fill", torchX, torchY - 35, (52 + flicker) * flame)
  love.graphics.setColor(1, 0.48, 0.12, 0.52 * flame)
  love.graphics.circle("fill", torchX, torchY - 30, (24 + flicker) * flame)
  love.graphics.setColor(1, 0.84, 0.34, 0.88 * flame)
  love.graphics.polygon("fill", torchX - 14, torchY - 18, torchX, torchY - 38 - flicker * 0.5 - fuel * 34, torchX + 14, torchY - 18, torchX + 5, torchY - 2, torchX - 6, torchY - 2)
  love.graphics.setColor(1, 0.95, 0.66, 0.88 * flame)
  love.graphics.polygon("fill", torchX - 6, torchY - 18, torchX + 1, torchY - 30 - fuel * 24, torchX + 8, torchY - 18, torchX + 2, torchY - 5)

  love.graphics.setColor(0.95, 0.48, 0.12, 0.04 + fuel * 0.06)
  love.graphics.circle("fill", width * 0.5, height * 0.55, max(width, height) * (0.24 + fuel * 0.2))
end

local function drawScene(game)
  local width, height = love.graphics.getDimensions()
  local depthBuffer = drawRaycastWorld(game, width, height)

  drawPickupSprites(game, width, height, depthBuffer)
  drawEnemySprite(game, width, height, depthBuffer)
  drawTorch(game, width, height)
end

function Renderer.draw(game)
  local width, height = love.graphics.getDimensions()

  if Renderer.postEnabled and Renderer.shader then
    ensureCanvas(width, height)
    love.graphics.setCanvas(Renderer.canvas)
    love.graphics.clear(0, 0, 0, 1)
    drawScene(game)
    love.graphics.setCanvas()
    Renderer.shader:send("time", game.survivalTime)
    Renderer.shader:send("fuel", game.torch.fuel)
    love.graphics.setShader(Renderer.shader)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(Renderer.canvas, 0, 0)
    love.graphics.setShader()
  else
    drawScene(game)
  end
end

function Renderer.togglePost()
  Renderer.postEnabled = not Renderer.postEnabled
end

return Renderer
