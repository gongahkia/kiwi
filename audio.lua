local Audio = {
  enabled = false,
  sources = {},
  growlTimer = 0,
}

local function sampleNoise(i)
  local value = (i * 1103515245 + 12345) % 65536
  return value / 32768 - 1
end

local function makeSource(kind, duration, volume, frequency)
  local rate = 22050
  local samples = math.floor(duration * rate)
  local data = love.sound.newSoundData(samples, rate, 16, 1)

  for i = 0, samples - 1 do
    local t = i / rate
    local wave

    if kind == "noise" then
      wave = sampleNoise(i)
    elseif kind == "growl" then
      wave = math.sin(t * (frequency or 52) * math.pi * 2) * 0.65 + sampleNoise(i) * 0.35
    else
      wave = math.sin(t * (frequency or 440) * math.pi * 2)
    end

    data:setSample(i, wave * volume)
  end

  return love.audio.newSource(data, "static")
end

local function play(source, volume, pitch, x, y, z)
  if not Audio.enabled or not source then
    return
  end

  local clone = source:clone()
  clone:setVolume(volume or 1)
  clone:setPitch(pitch or 1)

  if x and clone.setPosition then
    clone:setRelative(false)
    clone:setPosition(x, z or 0, y or 0)
  else
    clone:setRelative(true)
  end

  clone:play()
end

function Audio.init()
  local ok = pcall(function()
    Audio.sources.step = makeSource("noise", 0.075, 0.22)
    Audio.sources.water = makeSource("noise", 0.13, 0.18)
    Audio.sources.metal = makeSource("tone", 0.06, 0.16, 880)
    Audio.sources.relay = makeSource("tone", 0.22, 0.2, 620)
    Audio.sources.refill = makeSource("tone", 0.18, 0.16, 330)
    Audio.sources.growl = makeSource("growl", 0.62, 0.2, 48)
  end)

  Audio.enabled = ok
end

function Audio.step(terrain, sprinting)
  if terrain == "water" then
    play(Audio.sources.water, sprinting and 0.62 or 0.46, 0.7 + love.math.random() * 0.15)
  elseif terrain == "grate" or terrain == "catwalk" or terrain == "ladder" then
    play(Audio.sources.metal, sprinting and 0.46 or 0.32, 0.82 + love.math.random() * 0.18)
  else
    play(Audio.sources.step, sprinting and 0.5 or 0.34, 0.78 + love.math.random() * 0.28)
  end
end

function Audio.relay()
  play(Audio.sources.relay, 0.72, 1)
end

function Audio.refill()
  play(Audio.sources.refill, 0.56, 1)
end

function Audio.update(game, dt)
  if not Audio.enabled or not love.audio.setPosition then
    return
  end

  local player = game.player
  if player then
    love.audio.setPosition(player.x, player.floorZ or 0, player.y)
    love.audio.setOrientation(math.cos(player.angle), 0, math.sin(player.angle), 0, 1, 0)
  end

  Audio.growlTimer = math.max(0, Audio.growlTimer - dt)
end

function Audio.enemy(enemy, player)
  if not Audio.enabled or Audio.growlTimer > 0 or enemy.growl <= 0.55 then
    return
  end

  local dx, dy = enemy.x - player.x, enemy.y - player.y
  local distance = math.sqrt(dx * dx + dy * dy)
  local volume = math.max(0.08, math.min(0.74, 1 - distance / 22)) * enemy.growl

  play(Audio.sources.growl, volume, 0.88 + love.math.random() * 0.16, enemy.x, enemy.y, enemy.floorZ or 0)
  Audio.growlTimer = enemy.visible and 0.9 or 1.7
end

return Audio
