local Cycles = {}

Cycles.phases = {
  { id = "quiet", label = "QUIET", duration = { 16, 24 }, pulseEvery = 0, pressure = 0.15, salvageWindow = true },
  { id = "warning", label = "WARNING", duration = { 10, 15 }, pulseEvery = 5.5, pressure = 0.38, signal = "pressure_tick" },
  { id = "surge", label = "SURGE", duration = { 12, 18 }, pulseEvery = 4.0, pressure = 0.72, shelter = true },
  { id = "collapse", label = "COLLAPSE", duration = { 8, 13 }, pulseEvery = 3.0, pressure = 1.0, extractBias = true },
  { id = "aftermath", label = "AFTERMATH", duration = { 9, 14 }, pulseEvery = 7.5, pressure = 0.32, salvageWindow = true },
}

Cycles.biomeIncidents = {
  cryo_vault = { warning = "blackout", surge = "lockdown", collapse = "nest_wake", aftermath = "blackout" },
  fungal_service = { warning = "vent_bloom", surge = "nest_wake", collapse = "flood_surge", aftermath = "vent_bloom" },
  pressure_lab = { warning = "lockdown", surge = "blackout", collapse = "faction_raid", aftermath = "nest_wake" },
  reactor_trench = { warning = "heat_spike", surge = "vent_bloom", collapse = "blackout", aftermath = "heat_spike" },
  waste_artery = { warning = "flood_surge", surge = "nest_wake", collapse = "lockdown", aftermath = "flood_surge" },
  storm_drain = { warning = "flood_surge", surge = "flood_surge", collapse = "lockdown", aftermath = "vent_bloom" },
  ash_foundry = { warning = "heat_spike", surge = "heat_spike", collapse = "vent_bloom", aftermath = "blackout" },
  signal_catacombs = { warning = "blackout", surge = "vent_bloom", collapse = "nest_wake", aftermath = "blackout" },
  bone_market = { warning = "faction_raid", surge = "nest_wake", collapse = "lockdown", aftermath = "faction_raid" },
  organ_machine = { warning = "lockdown", surge = "flood_surge", collapse = "heat_spike", aftermath = "nest_wake" },
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
  return (map and map[phaseId]) or fallback or "nest_wake"
end

return Cycles
