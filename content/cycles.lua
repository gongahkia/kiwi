local Cycles = {}

Cycles.phases = {
  { id = "quiet", label = "QUIET", duration = { 16, 24 }, pulseEvery = 0, pressure = 0.15, salvageWindow = true },
  { id = "warning", label = "WARNING", duration = { 10, 15 }, pulseEvery = 5.5, pressure = 0.38, signal = "pressure_tick" },
  { id = "surge", label = "SURGE", duration = { 12, 18 }, pulseEvery = 4.0, pressure = 0.72, shelter = true },
  { id = "collapse", label = "COLLAPSE", duration = { 8, 13 }, pulseEvery = 3.0, pressure = 1.0, extractBias = true },
  { id = "aftermath", label = "AFTERMATH", duration = { 9, 14 }, pulseEvery = 7.5, pressure = 0.32, salvageWindow = true },
}

Cycles.biomeIncidents = {
  cryo_vault = { warning = "blackout", surge = "lockdown", collapse = "blackout", aftermath = "vent_bloom" },
  fungal_service = { warning = "vent_bloom", surge = "blackout", collapse = "lockdown", aftermath = "vent_bloom" },
  pressure_lab = { warning = "lockdown", surge = "blackout", collapse = "lockdown", aftermath = "vent_bloom" },
  reactor_trench = { warning = "vent_bloom", surge = "blackout", collapse = "lockdown", aftermath = "vent_bloom" },
  waste_artery = { warning = "blackout", surge = "vent_bloom", collapse = "lockdown", aftermath = "blackout" },
  storm_drain = { warning = "vent_bloom", surge = "blackout", collapse = "lockdown", aftermath = "vent_bloom" },
  ash_foundry = { warning = "blackout", surge = "vent_bloom", collapse = "lockdown", aftermath = "blackout" },
  signal_catacombs = { warning = "blackout", surge = "vent_bloom", collapse = "lockdown", aftermath = "blackout" },
  bone_market = { warning = "lockdown", surge = "blackout", collapse = "lockdown", aftermath = "vent_bloom" },
  organ_machine = { warning = "lockdown", surge = "blackout", collapse = "vent_bloom", aftermath = "lockdown" },
}

function Cycles.phaseAt(index)
  return Cycles.phases[((index - 1) % #Cycles.phases) + 1]
end

function Cycles.durationFor(phase)
  local range = phase.duration or { 10, 14 }
  return love.math.random(range[1], range[2])
end

function Cycles.incidentFor(biome, phaseId, fallback)
  local map = Cycles.biomeIncidents[biome or ""]
  return (map and map[phaseId]) or fallback or "blackout"
end

return Cycles
