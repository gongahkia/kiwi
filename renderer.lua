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
  crtShader = nil,
  monoShader = nil,
  renderMode = "mono",
  modes = { "normal", "crt", "mono" },
  modeIndex = 3,
  paletteIndex = 1,
  unlockedPalettes = 1,
}

Renderer.palettes = {
  { label = "Bone Lamp", unlockDeck = 1, paper = { 0.025, 0.024, 0.021 }, ink = { 0.86, 0.82, 0.64 } },
  { label = "Crimson Well", unlockDeck = 2, paper = { 0.035, 0.006, 0.01 }, ink = { 0.96, 0.66, 0.48 } },
  { label = "Frost Vault", unlockDeck = 3, paper = { 0.015, 0.023, 0.035 }, ink = { 0.68, 0.93, 1.0 } },
  { label = "Acid Signal", unlockDeck = 4, paper = { 0.01, 0.028, 0.018 }, ink = { 0.66, 1.0, 0.45 } },
  { label = "Royal Void", unlockDeck = 5, paper = { 0.018, 0.012, 0.03 }, ink = { 0.92, 0.76, 1.0 } },
}

local crtShaderSource = [[
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

local monoShaderSource = [[
extern vec2 screenSize;
extern number fuel;
extern vec3 paper;
extern vec3 ink;

number luminance(vec3 c) {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

number bayer2(vec2 p) {
  p = mod(floor(p), 2.0);
  if (p.y < 0.5) {
    return p.x < 0.5 ? 0.0 : 2.0;
  }
  return p.x < 0.5 ? 3.0 : 1.0;
}

number bayer4(vec2 p) {
  return 4.0 * bayer2(mod(p, 2.0)) + bayer2(floor(p / 2.0));
}

number bayer8(vec2 p) {
  return (4.0 * bayer4(mod(p, 4.0)) + bayer2(floor(p / 4.0)) + 0.5) / 64.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec2 px = 1.0 / screenSize;
  vec4 src = Texel(tex, uv) * color;

  number center = luminance(src.rgb);
  number north = luminance(Texel(tex, uv + vec2(0.0, -px.y)).rgb);
  number south = luminance(Texel(tex, uv + vec2(0.0, px.y)).rgb);
  number east = luminance(Texel(tex, uv + vec2(px.x, 0.0)).rgb);
  number west = luminance(Texel(tex, uv + vec2(-px.x, 0.0)).rgb);
  number average = (north + south + east + west) * 0.25;
  number edge = clamp(abs(east - west) + abs(south - north), 0.0, 1.0);
  number contrast = clamp(center + (center - average) * 0.92 + edge * 0.24, 0.0, 1.0);
  number exposure = 0.78 + fuel * 0.3;
  number tone = pow(clamp(contrast * exposure, 0.0, 1.0), 0.78);
  number vignette = smoothstep(0.82, 0.18, length(uv - vec2(0.5)));
  tone *= mix(0.84, 1.08, vignette);

  number threshold = bayer8(screen);
  number inkMask = step(threshold, tone);
  number edgeMask = step(0.18, edge) * step(0.18, center);
  inkMask = max(inkMask, edgeMask);

  return vec4(mix(paper, ink, inkMask), 1.0);
}
]]

function Renderer.init()
  local ok, shader = pcall(love.graphics.newShader, crtShaderSource)
  if ok then
    Renderer.crtShader = shader
  end

  local monoOk, monoShader = pcall(love.graphics.newShader, monoShaderSource)
  if monoOk then
    Renderer.monoShader = monoShader
  end
end

local function ensureCanvas(width, height)
  if not Renderer.canvas or Renderer.canvas:getWidth() ~= width or Renderer.canvas:getHeight() ~= height then
    Renderer.canvas = love.graphics.newCanvas(width, height)
    Renderer.canvas:setFilter("nearest", "nearest")
  end
end

local function drawToCanvas(width, height, drawCallback)
  ensureCanvas(width, height)

  love.graphics.push("all")
  love.graphics.setCanvas(Renderer.canvas)
  love.graphics.clear(0, 0, 0, 1)
  drawCallback()
  love.graphics.setCanvas()
  love.graphics.pop()
end

local function drawCanvasWithShader(shader)
  love.graphics.push("all")
  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(Renderer.canvas, 0, 0)
  love.graphics.pop()
end

local function paletteUnlockedBy(bestDeck)
  local unlocked = 1
  for i, palette in ipairs(Renderer.palettes) do
    if (bestDeck or 1) >= (palette.unlockDeck or 1) then
      unlocked = i
    end
  end
  return unlocked
end

function Renderer.setPaletteProgress(bestDeck)
  Renderer.unlockedPalettes = paletteUnlockedBy(bestDeck)
  Renderer.paletteIndex = U.clamp(Renderer.paletteIndex or 1, 1, Renderer.unlockedPalettes)
end

function Renderer.currentPalette()
  return Renderer.palettes[Renderer.paletteIndex] or Renderer.palettes[1]
end

function Renderer.cyclePalette(bestDeck)
  Renderer.setPaletteProgress(bestDeck)
  Renderer.paletteIndex = (Renderer.paletteIndex % Renderer.unlockedPalettes) + 1
  return Renderer.currentPalette()
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
  elseif segment.kind == "lock" then
    red, green, blue = 0.72, 0.5, 0.16
  elseif segment.kind == "riser" or segment.kind == "drop" then
    if cell.terrain == "water" then
      red, green, blue = 0.18, 0.32, 0.38
    elseif cell.terrain == "moss" then
      red, green, blue = 0.25, 0.38, 0.22
    elseif cell.terrain == "slag" then
      red, green, blue = 0.62, 0.25, 0.1
    elseif cell.terrain == "ice" then
      red, green, blue = 0.38, 0.56, 0.64
    elseif cell.terrain == "fungus" then
      red, green, blue = 0.28, 0.38, 0.18
    elseif cell.terrain == "pressure" then
      red, green, blue = 0.36, 0.38, 0.44
    elseif cell.terrain == "reactor" then
      red, green, blue = 0.58, 0.24, 0.08
    elseif cell.terrain == "sludge" then
      red, green, blue = 0.16, 0.28, 0.18
    elseif cell.terrain == "storm" then
      red, green, blue = 0.12, 0.25, 0.32
    elseif cell.terrain == "ash" then
      red, green, blue = 0.36, 0.31, 0.28
    elseif cell.terrain == "signal" then
      red, green, blue = 0.18, 0.36, 0.42
    elseif cell.terrain == "bone" then
      red, green, blue = 0.42, 0.38, 0.28
    elseif cell.terrain == "organ" then
      red, green, blue = 0.3, 0.13, 0.18
    elseif cell.terrain == "rubble" then
      red, green, blue = 0.4, 0.36, 0.3
    elseif cell.terrain == "tar" then
      red, green, blue = 0.08, 0.12, 0.1
    elseif cell.terrain == "thorn" then
      red, green, blue = 0.34, 0.26, 0.16
    elseif cell.terrain == "mirror" then
      red, green, blue = 0.46, 0.52, 0.56
    elseif cell.terrain == "drop" then
      red, green, blue = 0.018, 0.015, 0.012
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
  elseif (segment.kind == "sealed gate" or segment.kind == "lock") and distance < 16 then
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
  elseif cell.terrain == "ice" then
    red, green, blue = 0.20, 0.34, 0.42
  elseif cell.terrain == "fungus" then
    red, green, blue = 0.18, 0.25, 0.12
  elseif cell.terrain == "pressure" then
    red, green, blue = 0.25, 0.26, 0.30
  elseif cell.terrain == "reactor" then
    red, green, blue = 0.42, 0.15, 0.04
  elseif cell.terrain == "sludge" then
    red, green, blue = 0.09, 0.2, 0.12
  elseif cell.terrain == "storm" then
    red, green, blue = 0.06, 0.18, 0.24
  elseif cell.terrain == "ash" then
    red, green, blue = 0.24, 0.21, 0.19
  elseif cell.terrain == "signal" then
    red, green, blue = 0.12, 0.25, 0.3
  elseif cell.terrain == "bone" then
    red, green, blue = 0.3, 0.27, 0.2
  elseif cell.terrain == "organ" then
    red, green, blue = 0.2, 0.08, 0.12
  elseif cell.terrain == "glass" then
    red, green, blue = 0.25, 0.31, 0.34
  elseif cell.terrain == "dust" then
    red, green, blue = 0.28, 0.25, 0.18
  elseif cell.terrain == "tar" then
    red, green, blue = 0.035, 0.075, 0.055
  elseif cell.terrain == "thorn" then
    red, green, blue = 0.2, 0.16, 0.09
  elseif cell.terrain == "mirror" then
    red, green, blue = 0.34, 0.39, 0.42
  elseif cell.terrain == "drop" then
    red, green, blue = 0.012, 0.01, 0.008
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
  local floorZ = currentCell.floor
  local ceilingZ = currentCell.ceiling
  local floorDistanceScale = max(player.eyeZ - floorZ, 0.08) * projectionScale
  local ceilingDistanceScale = max(ceilingZ - player.eyeZ, 0.08) * projectionScale

  for y = ceil(horizon), height - 1, 2 do
    local distance = floorDistanceScale / max(y - horizon, 0.001)

    if distance < Renderer.wallRenderDistance then
      love.graphics.setColor(surfaceColor(currentCell, distance, false))
      love.graphics.rectangle("fill", 0, y, width, 2)
    end
  end

  for y = floor(horizon), 0, -2 do
    local distance = ceilingDistanceScale / max(horizon - y, 0.001)

    if distance < Renderer.wallRenderDistance then
      love.graphics.setColor(surfaceColor(currentCell, distance, true))
      love.graphics.rectangle("fill", 0, y - 1, width, 2)
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

local creatureColors = {
  hunter = { 0.18, 0.02, 0.018, 0.45, 0.035, 0.03 },
  stalker = { 0.04, 0.045, 0.08, 0.22, 0.26, 0.42 },
  skitter = { 0.12, 0.09, 0.03, 0.8, 0.56, 0.14 },
  screecher = { 0.08, 0.07, 0.1, 0.55, 0.48, 0.8 },
  burrower = { 0.14, 0.06, 0.025, 0.5, 0.24, 0.08 },
  mimic = { 0.16, 0.12, 0.02, 0.86, 0.68, 0.16 },
  warden = { 0.1, 0.08, 0.04, 0.72, 0.48, 0.16 },
  leecher = { 0.025, 0.08, 0.06, 0.22, 0.62, 0.48 },
  choir = { 0.1, 0.055, 0.11, 0.72, 0.38, 0.86 },
}

local function drawCreatureSprite(game, creature, width, height, depthBuffer)
  if not creature or not creature.alive then
    return
  end

  local sprite = projectSprite(game, creature.x, creature.y, creature.floorZ, creature.height or Actor.playerHeight, width, height)

  if not spriteVisible(sprite, width, depthBuffer) then
    return
  end

  local bodyAlpha = U.clamp(1 - sprite.distance / 28, 0.32, 1)
  local bodyWidth = sprite.width
  local headY = -sprite.height * 0.58
  local headRadius = max(3, bodyWidth * 0.21)
  local color = creatureColors[creature.kind] or creatureColors.hunter

  love.graphics.push()
  love.graphics.translate(sprite.x, sprite.y)

  love.graphics.setColor(0, 0, 0, 0.35 * bodyAlpha)
  love.graphics.ellipse("fill", 0, sprite.height * 0.03, bodyWidth * 0.36, max(2, sprite.height * 0.035))

  love.graphics.setColor(color[1], color[2], color[3], bodyAlpha)
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

  love.graphics.setColor(color[4], color[5], color[6], bodyAlpha)
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

  love.graphics.setColor(color[1] * 0.45, color[2] * 0.45, color[3] * 0.45, bodyAlpha)
  love.graphics.circle("fill", 0, headY, headRadius)

  local eyeGlow = 0.6 + (creature.growl or 0) * 0.4
  if creature.kind == "skitter" then
    love.graphics.setColor(1.0, 0.86, 0.28, bodyAlpha * eyeGlow)
  elseif creature.kind == "screecher" or creature.kind == "choir" then
    love.graphics.setColor(0.72, 0.58, 1.0, bodyAlpha * eyeGlow)
  elseif creature.kind == "leecher" then
    love.graphics.setColor(0.42, 1.0, 0.74, bodyAlpha * eyeGlow)
  else
    love.graphics.setColor(1.0, 0.76, 0.22, bodyAlpha * eyeGlow)
  end
  love.graphics.circle("fill", -headRadius * 0.38, headY - headRadius * 0.12, max(1.5, headRadius * 0.16))
  love.graphics.circle("fill", headRadius * 0.38, headY - headRadius * 0.12, max(1.5, headRadius * 0.16))

  love.graphics.setColor(0.02, 0, 0, bodyAlpha)
  love.graphics.setLineWidth(max(1, sprite.height * 0.012))
  love.graphics.line(-headRadius * 0.55, headY + headRadius * 0.38, headRadius * 0.55, headY + headRadius * 0.38)

  love.graphics.pop()
end

local function drawCreatures(game, width, height, depthBuffer)
  local drawList = {}
  for _, creature in ipairs(game.creatures or {}) do
    if creature.alive then
      drawList[#drawList + 1] = creature
    end
  end
  table.sort(drawList, function(a, b)
    local ad = (a.x - game.player.x) ^ 2 + (a.y - game.player.y) ^ 2
    local bd = (b.x - game.player.x) ^ 2 + (b.y - game.player.y) ^ 2
    return ad > bd
  end)
  for _, creature in ipairs(drawList) do
    drawCreatureSprite(game, creature, width, height, depthBuffer)
  end
end

local function drawNPCSprite(game, npc, width, height, depthBuffer)
  if not npc or not npc.alive then
    return
  end

  local sprite = projectSprite(game, npc.x, npc.y, npc.floorZ, npc.height or 1.4, width, height)
  if not spriteVisible(sprite, width, depthBuffer) then
    return
  end

  local alpha = U.clamp(1 - sprite.distance / 26, 0.34, 0.95)
  local color = npc.color or { 0.18, 0.36, 0.34, 0.58, 0.92, 0.78 }
  local bodyWidth = sprite.width * 0.82
  local headRadius = max(3, sprite.width * 0.17)
  local headY = -sprite.height * 0.7

  love.graphics.push()
  love.graphics.translate(sprite.x, sprite.y)

  love.graphics.setColor(0, 0, 0, 0.32 * alpha)
  love.graphics.ellipse("fill", 0, sprite.height * 0.03, bodyWidth * 0.34, max(2, sprite.height * 0.035))

  love.graphics.setColor(color[1], color[2], color[3], alpha)
  love.graphics.rectangle("fill", -bodyWidth * 0.22, -sprite.height * 0.58, bodyWidth * 0.44, sprite.height * 0.55, 3, 3)
  love.graphics.setColor(color[4], color[5], color[6], alpha)
  love.graphics.rectangle("line", -bodyWidth * 0.25, -sprite.height * 0.61, bodyWidth * 0.5, sprite.height * 0.6, 3, 3)
  love.graphics.rectangle("fill", -bodyWidth * 0.16, -sprite.height * 0.47, bodyWidth * 0.32, max(2, sprite.height * 0.06), 1, 1)

  love.graphics.setColor(0.18, 0.13, 0.08, alpha)
  love.graphics.circle("fill", 0, headY, headRadius)
  love.graphics.setColor(0.72, 1, 0.84, alpha)
  love.graphics.circle("fill", -headRadius * 0.32, headY - headRadius * 0.08, max(1.2, headRadius * 0.13))
  love.graphics.circle("fill", headRadius * 0.32, headY - headRadius * 0.08, max(1.2, headRadius * 0.13))

  if npc.state == "lead" then
    love.graphics.setColor(0.72, 1, 0.84, alpha * 0.72)
    love.graphics.line(0, -sprite.height * 0.38, bodyWidth * 0.34, -sprite.height * 0.5)
  elseif npc.state == "flee" then
    love.graphics.setColor(1, 0.62, 0.28, alpha * 0.8)
    love.graphics.line(-bodyWidth * 0.28, -sprite.height * 0.38, bodyWidth * 0.28, -sprite.height * 0.48)
  end

  love.graphics.pop()
end

local function drawNPCs(game, width, height, depthBuffer)
  local drawList = {}

  for _, npc in ipairs(game.npcs or {}) do
    if npc.alive then
      drawList[#drawList + 1] = npc
    end
  end

  table.sort(drawList, function(a, b)
    local ad = (a.x - game.player.x) ^ 2 + (a.y - game.player.y) ^ 2
    local bd = (b.x - game.player.x) ^ 2 + (b.y - game.player.y) ^ 2
    return ad > bd
  end)

  for _, npc in ipairs(drawList) do
    drawNPCSprite(game, npc, width, height, depthBuffer)
  end
end

local function drawPickupSprites(game, width, height, depthBuffer)
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

  for _, cache in ipairs(game.level.toolCaches or {}) do
    if not cache.cell.toolUsed then
      local sprite = projectSprite(game, cache.x + 0.5, cache.y + 0.5, cache.cell.floor + 0.08, 0.52, width, height)
      if spriteVisible(sprite, width, depthBuffer) then
        local alpha = U.clamp(1 - sprite.distance / 18, 0.24, 0.86)
        love.graphics.push()
        love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.3)
        love.graphics.setColor(0.35, 0.88, 0.72, alpha)
        love.graphics.rectangle("line", -sprite.width * 0.26, -sprite.height * 0.22, sprite.width * 0.52, sprite.height * 0.44, 2, 2)
        love.graphics.setColor(0.12, 0.28, 0.24, alpha * 0.86)
        love.graphics.rectangle("fill", -sprite.width * 0.2, -sprite.height * 0.16, sprite.width * 0.4, sprite.height * 0.32, 2, 2)
        love.graphics.pop()
      end
    end
  end

  for _, effect in ipairs(game.effects or {}) do
    if effect.kind == "flare" then
      local sprite = projectSprite(game, effect.x, effect.y, Actor.floorAt(game.level, effect.x, effect.y) + 0.08, 0.42, width, height)
      if spriteVisible(sprite, width, depthBuffer) then
        local alpha = U.clamp((effect.ttl or 0) / 9, 0.18, 0.95)
        love.graphics.push()
        love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.25)
        love.graphics.setColor(1, 0.42, 0.16, alpha)
        love.graphics.circle("fill", 0, 0, max(3, sprite.width * 0.22))
        love.graphics.setColor(1, 0.7, 0.24, alpha * 0.18)
        love.graphics.circle("fill", 0, 0, max(8, sprite.width * 0.9))
        love.graphics.pop()
      end
    end
  end

  for _, prop in ipairs(game.props or {}) do
    if prop.kind ~= "flare" and (prop.ttl or 0) > 0 then
      local sprite = projectSprite(game, prop.x, prop.y, Actor.floorAt(game.level, prop.x, prop.y) + 0.08, 0.35, width, height)
      if spriteVisible(sprite, width, depthBuffer) then
        local alpha = U.clamp((prop.ttl or 0) / 30, 0.24, 0.92)
        love.graphics.push()
        love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.22)
        if prop.kind == "scent" then
          love.graphics.setColor(0.36, 0.9, 0.58, alpha)
          love.graphics.circle("line", 0, 0, max(5, sprite.width * 0.28))
        elseif prop.kind == "snare" then
          love.graphics.setColor(0.82, 0.82, 0.72, prop.armed and alpha or alpha * 0.35)
          love.graphics.line(-sprite.width * 0.32, 0, sprite.width * 0.32, 0)
        elseif prop.kind == "noisemaker" then
          love.graphics.setColor(0.6, 0.9, 1, alpha)
          love.graphics.rectangle("line", -sprite.width * 0.2, -sprite.height * 0.12, sprite.width * 0.4, sprite.height * 0.24, 2, 2)
        elseif prop.kind == "pheromone" then
          love.graphics.setColor(0.32, 0.95, 0.52, alpha)
          love.graphics.circle("line", 0, 0, max(7, sprite.width * 0.38))
          love.graphics.line(-sprite.width * 0.28, 0, sprite.width * 0.28, 0)
        elseif prop.kind == "probe" then
          love.graphics.setColor(0.82, 0.9, 1, alpha)
          love.graphics.rectangle("line", -sprite.width * 0.18, -sprite.height * 0.18, sprite.width * 0.36, sprite.height * 0.36, 1, 1)
          love.graphics.circle("line", 0, 0, max(4, sprite.width * 0.22))
        elseif prop.kind == "beacon" then
          love.graphics.setColor(0.95, 0.55, 0.18, alpha)
          love.graphics.rectangle("line", -sprite.width * 0.2, -sprite.height * 0.22, sprite.width * 0.4, sprite.height * 0.44, 2, 2)
          love.graphics.line(-sprite.width * 0.32, -sprite.height * 0.3, sprite.width * 0.32, -sprite.height * 0.3)
        end
        love.graphics.pop()
      end
    end
  end

  for _, signal in ipairs(game.level.signals or {}) do
    if signal.discovered or (game.survey and game.survey.ttl > 0) then
      local sprite = projectSprite(game, signal.x, signal.y, Actor.floorAt(game.level, signal.x, signal.y) + 0.025, 0.18, width, height)
      if spriteVisible(sprite, width, depthBuffer) then
        local alpha = signal.discovered and U.clamp((signal.strength or 1) * 0.55, 0.24, 0.72) or 0.24
        love.graphics.push()
        love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.12)
        if signal.kind == "wet_tracks" then
          love.graphics.setColor(0.24, 0.58, 0.86, alpha)
        elseif signal.kind == "pheromone" then
          love.graphics.setColor(0.32, 0.92, 0.5, alpha)
        elseif signal.kind == "alarm_mark" or signal.kind == "scratch" then
          love.graphics.setColor(0.9, 0.2, 0.12, alpha)
        else
          love.graphics.setColor(0.9, 0.72, 0.38, alpha)
        end
        love.graphics.line(-sprite.width * 0.42, 0, sprite.width * 0.42, 0)
        love.graphics.line(0, -sprite.height * 0.18, 0, sprite.height * 0.18)
        love.graphics.pop()
      end
    end
  end

  for _, key in ipairs(game.level.keys or {}) do
    if not key.cell.key.collected then
      local sprite = projectSprite(game, key.x + 0.5, key.y + 0.5, key.cell.floor + 0.12, 0.45, width, height)
      if spriteVisible(sprite, width, depthBuffer) then
        local alpha = U.clamp(1 - sprite.distance / 18, 0.28, 0.9)
        love.graphics.push()
        love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.32)
        if key.kind == "exit" then
          love.graphics.setColor(1, 0.52, 0.16, alpha)
        else
          love.graphics.setColor(1, 0.82, 0.18, alpha)
        end
        love.graphics.circle("line", -sprite.width * 0.08, 0, max(3, sprite.width * 0.18))
        love.graphics.rectangle("fill", 0, -sprite.height * 0.04, sprite.width * 0.32, max(2, sprite.height * 0.08), 1, 1)
        love.graphics.rectangle("fill", sprite.width * 0.2, -sprite.height * 0.04, max(2, sprite.width * 0.06), sprite.height * 0.18, 1, 1)
        love.graphics.pop()
      end
    end
  end

  if game.level.exit then
    local exit = game.level.exit
    local sprite = projectSprite(game, exit.x + 0.5, exit.y + 0.5, exit.cell.floor + 0.08, 0.95, width, height)
    if spriteVisible(sprite, width, depthBuffer) then
      local alpha = U.clamp(1 - sprite.distance / 24, 0.3, 0.92)
      love.graphics.push()
      love.graphics.translate(sprite.x, sprite.y - sprite.height * 0.5)
      love.graphics.setColor(0.02, 0.015, 0.01, alpha)
      love.graphics.ellipse("fill", 0, sprite.height * 0.08, sprite.width * 0.54, sprite.height * 0.24)
      love.graphics.setColor(0.98, 0.7, 0.22, alpha)
      love.graphics.ellipse("line", 0, sprite.height * 0.08, sprite.width * 0.56, sprite.height * 0.26)
      love.graphics.line(-sprite.width * 0.36, -sprite.height * 0.14, sprite.width * 0.36, -sprite.height * 0.14)
      love.graphics.line(-sprite.width * 0.22, -sprite.height * 0.27, sprite.width * 0.22, -sprite.height * 0.27)
      love.graphics.pop()
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
  drawNPCs(game, width, height, depthBuffer)
  drawCreatures(game, width, height, depthBuffer)
  drawTorch(game, width, height)
end

function Renderer.draw(game)
  drawScene(game)
end

function Renderer.drawFrame(game, drawCallback)
  local width, height = love.graphics.getDimensions()

  if Renderer.renderMode == "normal" then
    drawCallback()
  elseif Renderer.renderMode == "crt" and Renderer.crtShader then
    drawToCanvas(width, height, drawCallback)
    Renderer.crtShader:send("time", game.survivalTime)
    Renderer.crtShader:send("fuel", game.torch.fuel)
    drawCanvasWithShader(Renderer.crtShader)
  elseif Renderer.renderMode == "mono" and Renderer.monoShader then
    drawToCanvas(width, height, drawCallback)
    local palette = Renderer.currentPalette()
    Renderer.monoShader:send("screenSize", { width, height })
    Renderer.monoShader:send("fuel", game.torch.fuel)
    Renderer.monoShader:send("paper", palette.paper)
    Renderer.monoShader:send("ink", palette.ink)
    drawCanvasWithShader(Renderer.monoShader)
  else
    drawCallback()
  end
end

function Renderer.togglePost()
  for _ = 1, #Renderer.modes do
    Renderer.modeIndex = (Renderer.modeIndex % #Renderer.modes) + 1
    local mode = Renderer.modes[Renderer.modeIndex]
    if mode == "normal" or (mode == "crt" and Renderer.crtShader) or (mode == "mono" and Renderer.monoShader) then
      Renderer.renderMode = mode
      return Renderer.renderMode
    end
  end
  Renderer.modeIndex = 1
  Renderer.renderMode = "normal"
  return Renderer.renderMode
end

return Renderer
