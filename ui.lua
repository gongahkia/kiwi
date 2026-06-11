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
  if cell.lock and cell.lock.locked then
    return 0.8, 0.62, 0.22
  elseif cell.gateLocked then
    return 0.78, 0.52, 0.12
  elseif cell.exit then
    return 0.95, 0.72, 0.24
  elseif cell.terminal then
    return 0.25, 0.72, 0.68
  elseif Level.isHazardActive(cell) then
    if cell.hazard.kind == "ember" then
      return 0.72, 0.22, 0.08
    elseif cell.hazard.kind == "wire" then
      return 0.62, 0.62, 0.32
    end
    return 0.34, 0.22, 0.18
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
  elseif cell.terrain == "ice" then
    return 0.42, 0.62, 0.72
  elseif cell.terrain == "fungus" then
    return 0.36, 0.48, 0.24
  elseif cell.terrain == "pressure" then
    return 0.42, 0.44, 0.5
  elseif cell.terrain == "reactor" then
    return 0.72, 0.34, 0.12
  elseif cell.terrain == "sludge" then
    return 0.18, 0.34, 0.22
  elseif cell.terrain == "storm" then
    return 0.1, 0.26, 0.34
  elseif cell.terrain == "ash" then
    return 0.38, 0.33, 0.3
  elseif cell.terrain == "signal" then
    return 0.24, 0.42, 0.5
  elseif cell.terrain == "bone" then
    return 0.52, 0.48, 0.38
  elseif cell.terrain == "organ" then
    return 0.35, 0.18, 0.24
  elseif cell.terrain == "glass" then
    return 0.42, 0.52, 0.58
  elseif cell.terrain == "dust" then
    return 0.42, 0.38, 0.28
  elseif cell.salvage then
    return 0.24, 0.38, 0.32
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
  local function cellCenter(x, y)
    return originX + (x - 0.5) * size, originY + (y - 0.5) * size
  end
  local function drawMarker(x, y, red, green, blue, kind)
    local cx, cy = cellCenter(x, y)
    local radius = max(5, size * 1.8)

    love.graphics.setLineWidth(2)
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.circle("fill", cx, cy, radius + 2)
    love.graphics.setColor(red, green, blue, 0.96)
    if kind == "diamond" then
      love.graphics.polygon("fill", cx, cy - radius, cx + radius, cy, cx, cy + radius, cx - radius, cy)
      love.graphics.setColor(0, 0, 0, 0.65)
      love.graphics.line(cx - radius * 0.45, cy, cx + radius * 0.45, cy)
      love.graphics.line(cx, cy - radius * 0.45, cx, cy + radius * 0.45)
    else
      love.graphics.rectangle("fill", cx - radius, cy - radius, radius * 2, radius * 2)
      love.graphics.setColor(0, 0, 0, 0.65)
      love.graphics.rectangle("line", cx - radius * 0.55, cy - radius * 0.55, radius * 1.1, radius * 1.1)
    end
    love.graphics.setLineWidth(1)
  end

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

  drawMarker(level.start.x, level.start.y, 0.42, 0.95, 1, "square")
  if level.exit then
    drawMarker(level.exit.x, level.exit.y, 1, 0.74, 0.16, "diamond")
  end

  for _, objective in ipairs(level.objectives) do
    if not objective.cell.objective.collected then
      love.graphics.setColor(0.4, 0.95, 1, 0.95)
      love.graphics.rectangle("fill", originX + (objective.x - 1) * size, originY + (objective.y - 1) * size, max(2, size), max(2, size))
    end
  end

  for _, key in ipairs(level.keys or {}) do
    if not key.cell.key.collected then
      love.graphics.setColor(1, 0.86, 0.26, 0.95)
      love.graphics.rectangle("fill", originX + (key.x - 1) * size, originY + (key.y - 1) * size, max(2, size), max(2, size))
    end
  end

  for _, lock in ipairs(level.locks or {}) do
    if lock.cell.lock.locked then
      love.graphics.setColor(0.95, 0.62, 0.12, 0.95)
      love.graphics.rectangle("line", originX + (lock.x - 1) * size, originY + (lock.y - 1) * size, max(2, size), max(2, size))
    end
  end

  if level.exit and game.objectives.collected >= (level.minLiftRelays or game.objectives.total) then
    love.graphics.setColor(1, 0.78, 0.24, 0.96)
    love.graphics.rectangle("fill", originX + (level.exit.x - 1) * size, originY + (level.exit.y - 1) * size, max(3, size * 1.4), max(3, size * 1.4))
  end

  if level.scanRevealed then
    for _, terminal in ipairs(level.terminals or {}) do
      love.graphics.setColor(0.18, 1, 0.78, terminal.terminal.used and 0.42 or 0.95)
      love.graphics.rectangle("line", originX + (terminal.x - 1) * size, originY + (terminal.y - 1) * size, max(3, size * 1.4), max(3, size * 1.4))
    end
  end

  for _, refill in ipairs(level.refills) do
    if not refill.cell.refillUsed then
      love.graphics.setColor(1, 0.6, 0.16, 0.9)
      love.graphics.circle("fill", originX + refill.x * size - size, originY + refill.y * size - size, max(1.8, size * 0.45))
    end
  end

  for _, nest in ipairs(level.nests or {}) do
    love.graphics.setColor(0.78, 0.28, 0.88, 0.9)
    love.graphics.circle("line", originX + nest.x * size - size, originY + nest.y * size - size, max(3, size * 0.85))
  end

  for _, prop in ipairs(game.props or {}) do
    if (prop.ttl or 0) > 0 then
      love.graphics.setColor(0.7, 0.9, 1, 0.82)
      love.graphics.rectangle("fill", originX + prop.x * size - size, originY + prop.y * size - size, max(2, size * 0.55), max(2, size * 0.55))
    end
  end

  for _, signal in ipairs(level.signals or {}) do
    if signal.discovered or (game.survey and game.survey.ttl > 0) then
      local alpha = signal.discovered and 0.8 or 0.36
      if signal.kind == "pheromone" then
        love.graphics.setColor(0.34, 0.95, 0.54, alpha)
      elseif signal.kind == "alarm_mark" or signal.kind == "scratch" then
        love.graphics.setColor(0.95, 0.28, 0.18, alpha)
      elseif signal.kind == "wet_tracks" then
        love.graphics.setColor(0.28, 0.62, 0.92, alpha)
      else
        love.graphics.setColor(0.9, 0.76, 0.42, alpha)
      end
      love.graphics.circle("line", originX + signal.x * size - size, originY + signal.y * size - size, max(2, size * 0.55))
    end
  end

  local player = game.player
  local enemy = game.enemy or { x = player.x, y = player.y, path = {}, state = "clear", kind = "none", floorZ = player.floorZ }
  local px = originX + player.x * size - size
  local py = originY + player.y * size - size
  local ex = originX + enemy.x * size - size
  local ey = originY + enemy.y * size - size

  love.graphics.setColor(1, 0.78, 0.3, 0.95)
  love.graphics.circle("fill", px, py, max(2.5, size * 0.58))
  love.graphics.line(px, py, px + cos(player.angle) * size * 2.4, py + sin(player.angle) * size * 2.4)

  for _, creature in ipairs(game.creatures or {}) do
    if creature.alive then
      local cx = originX + creature.x * size - size
      local cy = originY + creature.y * size - size
      if creature.kind == "skitter" then
        love.graphics.setColor(1, 0.75, 0.18, 0.86)
      elseif creature.kind == "stalker" then
        love.graphics.setColor(0.35, 0.45, 0.9, 0.86)
      elseif creature.kind == "screecher" then
        love.graphics.setColor(0.75, 0.58, 1, 0.86)
      elseif creature.kind == "burrower" then
        love.graphics.setColor(0.75, 0.32, 0.12, 0.86)
      elseif creature.kind == "warden" then
        love.graphics.setColor(0.48, 0.82, 0.88, 0.9)
      elseif creature.kind == "leecher" then
        love.graphics.setColor(0.18, 0.76, 0.72, 0.88)
      elseif creature.kind == "mimic" then
        love.graphics.setColor(0.92, 0.82, 0.32, 0.9)
      elseif creature.kind == "choir" then
        love.graphics.setColor(0.82, 0.52, 1, 0.88)
      elseif creature.kind == "scavenger" then
        love.graphics.setColor(0.92, 0.56, 0.26, 0.88)
      else
        love.graphics.setColor(0.9, 0.08, 0.05, 0.95)
      end
      love.graphics.circle("fill", cx, cy, max(2.5, size * 0.58))
    end
  end

  love.graphics.setColor(0.9, 0.08, 0.05, 0.22)
  for i = 1, #enemy.path - 1 do
    local a = enemy.path[i]
    local b = enemy.path[i + 1]
    love.graphics.line(originX + a.x * size - size, originY + a.y * size - size, originX + b.x * size - size, originY + b.y * size - size)
  end
end

local function nearTerminal(game)
  local px = floor(game.player.x)
  local py = floor(game.player.y)

  for _, terminal in ipairs(game.level.terminals or {}) do
    if math.abs(terminal.x - px) + math.abs(terminal.y - py) <= 1 then
      return terminal
    end
  end

  return nil
end

local function drawHud(game, width, height)
  local player = game.player
  local enemy = game.enemy or { x = player.x, y = player.y, floorZ = player.floorZ, state = "clear", kind = "none" }
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
  love.graphics.rectangle("fill", 18, 18, 356, 334, 4, 4)

  love.graphics.setColor(0.95, 0.88, 0.68)
  love.graphics.print(string.format("TIME   %05.1f", game.survivalTime), 30, 28)
  love.graphics.setColor(0.86 + danger * 0.14, 0.78 - danger * 0.48, 0.55 - danger * 0.45)
  love.graphics.print(string.format("THREAT %02dM %-8s %-7s", floor(distance), string.upper(enemy.kind or "NONE"), string.upper(enemy.state or "WANDER")), 30, 55)
  love.graphics.setColor(0.78, 0.72, 0.6)
  love.graphics.print(string.format("DECK   %02d/%02d", game.deck or 1, game.maxDecks or 1), 30, 82)
  love.graphics.setColor(0.82, 0.76, 0.62)
  love.graphics.print(string.format("RELAY  %d/%d  PWR %d/%d", game.objectives.collected, game.objectives.total, game.level.power.assigned or 0, Level.powerCapacity(game.level)), 30, 109)
  if game.keys and game.keys.total > 0 then
    love.graphics.print(string.format("KEY %d/%d", game.keys.collected, game.keys.total), 206, 109)
  end
  if game.level.liftRequired then
    love.graphics.setColor(game.level.liftAuthorized and 0.42 or 0.86, game.level.liftAuthorized and 0.95 or 0.62, 0.58)
    love.graphics.print(game.level.liftAuthorized and "TERM   LIFT OK" or "TERM   LIFT REQ", 206, 136)
  end
  love.graphics.setColor(0.84, 0.64, 0.36)
  love.graphics.print(string.format("TORCH  %03d%%", floor(game.torch.fuel * 100)), 30, 136)
  love.graphics.setColor(0.68, 0.64, 0.56)
  love.graphics.print(traversal .. "  " .. zone, 30, 163)
  love.graphics.setColor(0.58, 0.56, 0.5)
  love.graphics.print(string.format("SEED   %d", game.seed), 30, 190)

  local systems = game.level.systems or {}
  local systemText = string.format(
    "SYS    L%s D%s P%s V%s C%s X%s",
    systems.lights and systems.lights.powered and "+" or "-",
    systems.doors and systems.doors.powered and "+" or "-",
    systems.pumps and systems.pumps.powered and "+" or "-",
    systems.vents and systems.vents.powered and "+" or "-",
    systems.decoy and systems.decoy.powered and "+" or "-",
    systems.lift and systems.lift.powered and "+" or "-"
  )
  love.graphics.setColor(0.62, 0.78, 0.7)
  love.graphics.print(systemText, 30, 217)

  local cycle = game.ecology and game.ecology.cycle
  local incident = game.ecology and game.ecology.active or "quiet"
  local phase = cycle and cycle.label or string.upper(incident)
  love.graphics.setColor(0.84, 0.67, 0.46)
  love.graphics.print(string.format("ECO    %-8s %03d %s", phase:sub(1, 8), floor(cycle and cycle.timer or 0), string.upper(incident):sub(1, 8)), 30, 244)

  local inv = game.inventory or {}
  love.graphics.setColor(0.78, 0.72, 0.6)
  local selected = inv.selected or "flare"
  love.graphics.print(string.format("TOOL   %-10s x%d  CODEX C", string.upper(selected), inv[selected] or 0), 30, 271)

  local biome = game.level.biomeProfile and game.level.biomeProfile.label or "UNKNOWN"
  love.graphics.setColor(0.54, 0.78, 0.76)
  love.graphics.print(string.format("BIO    %-12s SALV %d/%d", biome:sub(1, 12), game.salvage and game.salvage.carried or 0, game.unlocks and game.unlocks.salvage or 0), 30, 298)

  if game.demoMode then
    love.graphics.setColor(0.52, 0.82, 1, 0.9)
    love.graphics.print("DEMO", 310, 271)
  end

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

  local terminal = nearTerminal(game)
  if terminal and not game.terminal.active then
    love.graphics.setColor(0.1, 0.16, 0.14, 0.76)
    love.graphics.rectangle("fill", width * 0.5 - 138, height - 120, 276, 34, 3, 3)
    love.graphics.setColor(0.54, 1, 0.82)
    love.graphics.printf("F  " .. terminal.terminal.label .. "  " .. terminal.command, width * 0.5 - 128, height - 113, 256, "center")
  end
end

local function drawTerminalOverlay(game, width, height)
  if not game.terminal or not game.terminal.active then
    return
  end

  local terminal = game.terminal.current or { label = "T??", command = "SCAN", logs = {} }
  local panelWidth = min(width - 80, 680)
  local panelHeight = min(height - 80, 360)
  local x = (width - panelWidth) * 0.5
  local y = (height - panelHeight) * 0.5

  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 0, 0, width, height)
  love.graphics.setColor(0.04, 0.09, 0.08, 0.96)
  love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 4, 4)
  love.graphics.setColor(0.2, 0.9, 0.7, 0.92)
  love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 4, 4)

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0.58, 1, 0.82)
  love.graphics.print(string.format("%s  DECK %02d  ACCESS %s", terminal.label, game.deck or 1, terminal.command), x + 22, y + 18)
  love.graphics.setColor(0.38, 0.78, 0.66)
  love.graphics.print("1 LIGHTS 2 DOORS 3 PUMPS 4 VENTS 5 DECOY 6 LIFT", x + 22, y + 46)

  love.graphics.setColor(0.12, 0.23, 0.2, 0.9)
  love.graphics.rectangle("fill", x + 20, y + 78, panelWidth - 40, panelHeight - 144)

  local logs = terminal.logs or {}
  local logY = y + 90
  love.graphics.setColor(0.72, 0.95, 0.82)
  for i = max(1, #logs - 7), #logs do
    love.graphics.print(logs[i], x + 34, logY)
    logY = logY + 23
  end

  love.graphics.setColor(0.04, 0.08, 0.07, 0.96)
  love.graphics.rectangle("fill", x + 20, y + panelHeight - 54, panelWidth - 40, 34)
  love.graphics.setColor(0.58, 1, 0.82)
  love.graphics.print("> " .. (game.terminal.input or ""), x + 34, y + panelHeight - 47)
  love.graphics.setColor(0.38, 0.78, 0.66)
  love.graphics.printf("ENTER RUN   ESC EXIT   TYPED: SCAN UNLOCK PURGE", x + 20, y + panelHeight - 47, panelWidth - 52, "right")
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
  love.graphics.printf(string.format("TIME %.1f   BEST %.1f   DECK %02d   SEED %d", game.survivalTime, game.bestTime, game.deck or 1, game.seed), 0, height * 0.49, width, "center")
  love.graphics.setColor(0.82, 0.76, 0.66)
  love.graphics.printf("R REPLAY   N NEW RUN", 0, height * 0.58, width, "center")
end

local function drawRouteSelect(game, width, height)
  if game.state ~= "route_select" then
    return
  end

  local choices = game.routeChoices or {}
  local panelWidth = min(width - 80, 860)
  local panelHeight = min(height - 80, 430)
  local x = (width - panelWidth) * 0.5
  local y = (height - panelHeight) * 0.5

  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 0, 0, width, height)
  love.graphics.setColor(0.07, 0.065, 0.055, 0.98)
  love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 4, 4)
  love.graphics.setColor(0.86, 0.68, 0.38, 0.95)
  love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 4, 4)

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0.96, 0.86, 0.58)
  love.graphics.print("DESCENT ROUTE", x + 24, y + 20)
  love.graphics.setColor(0.64, 0.6, 0.5)
  love.graphics.printf("1-3 SELECT  ENTER CONFIRM", x + 24, y + 20, panelWidth - 48, "right")

  local cardWidth = (panelWidth - 72) / max(1, #choices)
  for i, choice in ipairs(choices) do
    local cardX = x + 24 + (i - 1) * cardWidth
    local selected = i == (game.routeIndex or 1)
    love.graphics.setColor(selected and 0.22 or 0.11, selected and 0.17 or 0.115, selected and 0.085 or 0.07, 0.94)
    love.graphics.rectangle("fill", cardX, y + 64, cardWidth - 12, panelHeight - 104, 4, 4)
    love.graphics.setColor(selected and 0.98 or 0.76, selected and 0.8 or 0.68, selected and 0.42 or 0.54)
    love.graphics.rectangle("line", cardX, y + 64, cardWidth - 12, panelHeight - 104, 4, 4)

    local lineY = y + 82
    love.graphics.setColor(0.95, 0.86, 0.62)
    love.graphics.print(i .. "  " .. choice.label, cardX + 14, lineY)
    lineY = lineY + 34
    love.graphics.setColor(0.7, 0.92, 0.86)
    love.graphics.print(choice.biomeLabel or "UNKNOWN", cardX + 14, lineY)
    lineY = lineY + 30
    love.graphics.setColor(0.82, 0.76, 0.62)
    love.graphics.print("RISK " .. choice.risk .. "  SALVAGE " .. choice.salvage, cardX + 14, lineY)
    lineY = lineY + 28
    love.graphics.setColor(0.72, 0.68, 0.58)
    love.graphics.printf(choice.description or "", cardX + 14, lineY, cardWidth - 40)
    lineY = lineY + 72
    love.graphics.setColor(0.82, 0.72, 0.5)
    love.graphics.print("FACTION " .. (choice.previewFaction and string.upper(choice.faction or "UNKNOWN") or "UNKNOWN"), cardX + 14, lineY)
    lineY = lineY + 28
    love.graphics.print("INCIDENT " .. (choice.previewIncident and string.upper(choice.incident or "UNKNOWN") or "UNKNOWN"), cardX + 14, lineY)
    if choice.rareCache then
      love.graphics.setColor(0.52, 0.9, 0.72)
      love.graphics.print("RARE CACHE SIGNAL", cardX + 14, lineY + 28)
    end
  end
end

local function drawCodex(game, width, height)
  if not game.codexOpen then
    return
  end

  local panelWidth = min(width - 90, 760)
  local panelHeight = min(height - 90, 420)
  local x = (width - panelWidth) * 0.5
  local y = (height - panelHeight) * 0.5
  local entries = game.codex and game.codex.entries or {}

  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 0, 0, width, height)
  love.graphics.setColor(0.08, 0.08, 0.07, 0.96)
  love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 4, 4)
  love.graphics.setColor(0.86, 0.72, 0.44, 0.95)
  love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 4, 4)

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0.95, 0.86, 0.62)
  love.graphics.print("CODEX", x + 22, y + 18)
  love.graphics.setColor(0.66, 0.62, 0.54)
  love.graphics.printf("C CLOSE", x + 22, y + 18, panelWidth - 44, "right")

  local start = max(1, #entries - 10)
  local lineY = y + 54
  if #entries == 0 then
    love.graphics.setColor(0.72, 0.68, 0.58)
    love.graphics.print("NO DISCOVERIES", x + 22, lineY)
    return
  end

  for i = start, #entries do
    local entry = entries[i]
    love.graphics.setColor(0.5, 0.88, 0.76)
    love.graphics.print(string.upper(entry.kind) .. " / " .. string.upper(entry.id), x + 22, lineY)
    love.graphics.setColor(0.86, 0.82, 0.7)
    love.graphics.printf(entry.text, x + 22, lineY + 20, panelWidth - 44)
    lineY = lineY + 54
  end
end

local function drawToolWheel(game, width, height)
  if not game.toolWheel or not game.toolWheel.visible then
    return
  end

  local order = game.toolOrder or {}
  local inv = game.inventory or {}
  local cx = width * 0.5
  local cy = height * 0.52
  local radius = min(width, height) * 0.22

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0, 0, 0, 0.56)
  love.graphics.circle("fill", cx, cy, radius + 48)

  for i, tool in ipairs(order) do
    local angle = (i / #order) * math.pi * 2 - math.pi * 0.5
    local x = cx + cos(angle) * radius
    local y = cy + sin(angle) * radius
    local selected = tool == inv.selected
    love.graphics.setColor(selected and 0.9 or 0.22, selected and 0.76 or 0.28, selected and 0.38 or 0.26, selected and 0.95 or 0.82)
    love.graphics.circle("fill", x, y, selected and 34 or 27)
    love.graphics.setColor(0.04, 0.035, 0.028, 0.92)
    love.graphics.printf(tostring(inv[tool] or 0), x - 18, y - 8, 36, "center")
    love.graphics.setColor(0.95, 0.88, 0.68, 0.94)
    love.graphics.printf(string.upper(tool):sub(1, 4), x - 42, y + 28, 84, "center")
  end
end

local function drawPause(game, width, height)
  if not game.paused then
    return
  end

  local actions = game.bindingActions or {}
  local panelWidth = min(width - 90, 620)
  local panelHeight = min(height - 90, 460)
  local x = (width - panelWidth) * 0.5
  local y = (height - panelHeight) * 0.5

  love.graphics.setColor(0, 0, 0, 0.78)
  love.graphics.rectangle("fill", 0, 0, width, height)
  love.graphics.setColor(0.08, 0.075, 0.065, 0.98)
  love.graphics.rectangle("fill", x, y, panelWidth, panelHeight, 4, 4)
  love.graphics.setColor(0.86, 0.72, 0.44, 0.95)
  love.graphics.rectangle("line", x, y, panelWidth, panelHeight, 4, 4)

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0.95, 0.86, 0.62)
  love.graphics.print("PAUSED", x + 24, y + 20)
  love.graphics.setColor(0.66, 0.62, 0.54)
  love.graphics.printf("UP/DOWN SELECT  ENTER REBIND  BACKSPACE RESET", x + 24, y + 20, panelWidth - 48, "right")

  local lineY = y + 64
  for i, action in ipairs(actions) do
    local selected = i == (game.settingsIndex or 1)
    love.graphics.setColor(selected and 0.22 or 0.11, selected and 0.18 or 0.12, selected and 0.09 or 0.08, 0.92)
    love.graphics.rectangle("fill", x + 24, lineY - 4, panelWidth - 48, 24)
    love.graphics.setColor(selected and 0.98 or 0.74, selected and 0.86 or 0.7, selected and 0.56 or 0.58)
    love.graphics.print(string.upper(action), x + 34, lineY)
    love.graphics.printf(string.upper(game.bindings[action] or ""), x + 24, lineY, panelWidth - 66, "right")
    lineY = lineY + 28
  end

  if game.bindTarget then
    love.graphics.setColor(0.95, 0.76, 0.38)
    love.graphics.printf("PRESS A KEY FOR " .. string.upper(game.bindTarget), x + 24, y + panelHeight - 42, panelWidth - 48, "center")
  end
end

function UI.draw(game)
  local width, height = love.graphics.getDimensions()
  drawMinimap(game, width, height)
  drawHud(game, width, height)
  drawEndState(game, width, height)
  drawRouteSelect(game, width, height)
  drawToolWheel(game, width, height)
  drawTerminalOverlay(game, width, height)
  drawCodex(game, width, height)
  drawPause(game, width, height)
end

return UI
