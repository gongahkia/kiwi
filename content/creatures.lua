local Creatures = {}

Creatures.defs = {
  hunter = { radius = 0.2, baseSpeed = 1.18, sightSpeed = 1.68, sight = 24, hearing = 10, aggression = 1, height = 1.55, lethal = true },
  stalker = { radius = 0.18, baseSpeed = 1.02, sightSpeed = 1.92, sight = 18, hearing = 7, aggression = 0.72, height = 1.35, lethal = true },
  skitter = { radius = 0.14, baseSpeed = 1.34, sightSpeed = 1.72, sight = 12, hearing = 9, aggression = 0.1, height = 0.55, lethal = false },
  screecher = { radius = 0.18, baseSpeed = 0.95, sightSpeed = 1.52, sight = 6, hearing = 18, aggression = 0.86, height = 1.18, lethal = true },
  burrower = { radius = 0.22, baseSpeed = 0.78, sightSpeed = 1.18, sight = 10, hearing = 8, aggression = 0.62, height = 0.85, lethal = true },
  mimic = { radius = 0.17, baseSpeed = 0.38, sightSpeed = 1.7, sight = 10, hearing = 5, aggression = 0.8, height = 0.62, lethal = true, dormant = true },
  warden = { radius = 0.21, baseSpeed = 0.82, sightSpeed = 1.38, sight = 14, hearing = 9, aggression = 0.7, height = 1.48, lethal = true, guard = true },
  leecher = { radius = 0.16, baseSpeed = 0.88, sightSpeed = 1.52, sight = 9, hearing = 11, aggression = 0.74, height = 0.5, lethal = true, aquatic = true },
  choir = { radius = 0.17, baseSpeed = 1.08, sightSpeed = 1.56, sight = 7, hearing = 20, aggression = 0.82, height = 1.05, lethal = true, flock = true },
}

Creatures.predatorRank = {
  skitter = 0,
  stalker = 1,
  screecher = 2,
  burrower = 2,
  mimic = 2,
  leecher = 2,
  choir = 2,
  warden = 2,
  hunter = 3,
}

Creatures.toolAffinity = {
  hunter = { scent = 34, noisemaker = 22, flare = 10, pheromone = -38, probe = 8, beacon = 18, snare = 2 },
  stalker = { scent = 28, noisemaker = 15, flare = -55, pheromone = -30, probe = 12, beacon = 8, snare = 2 },
  skitter = { scent = 18, noisemaker = 10, pheromone = 14, probe = 32, beacon = 28, snare = 8 },
  screecher = { scent = 8, noisemaker = 44, flare = 8, pheromone = -8, probe = 20, beacon = 30, snare = 2 },
  burrower = { scent = 10, noisemaker = 12, pheromone = 30, probe = 4, beacon = 8, snare = 2 },
  mimic = { probe = -48, flare = -20, beacon = 22, noisemaker = 14, scent = 10 },
  warden = { scent = 12, noisemaker = 18, flare = 4, pheromone = -18, probe = 22, beacon = 14, snare = 4 },
  leecher = { scent = 24, noisemaker = 12, flare = -22, pheromone = 10, probe = 8, beacon = 10, snare = 4 },
  choir = { scent = 6, noisemaker = 52, flare = 6, pheromone = -10, probe = 24, beacon = 42, snare = 2 },
}

Creatures.signalAffinity = {
  hunter = { track = 28, scratch = 22, scent_trail = 30, nest_debris = 14, wet_tracks = 8, ash_drift = -4, vent_call = 14, alarm_mark = 22, pheromone = -34, survey_ping = 8, dark_pulse = 10, frost_trace = 8, spore_bloom = 20, pressure_tick = 18, radiant_heat = 6, tainted_sludge = 12, surge_line = 10, smoke_veil = -4, false_ping = 16, trade_mark = 18, pulse_mark = 16 },
  stalker = { track = 24, scratch = 30, scent_trail = 26, nest_debris = 8, wet_tracks = 4, ash_drift = 4, vent_call = 8, alarm_mark = 18, pheromone = -28, survey_ping = 12, dark_pulse = 36, frost_trace = 24, spore_bloom = 12, pressure_tick = 14, radiant_heat = -6, tainted_sludge = 4, surge_line = 6, smoke_veil = 24, false_ping = 18, trade_mark = 10, pulse_mark = 12 },
  skitter = { track = -16, scratch = -18, scent_trail = 12, nest_debris = 32, wet_tracks = 8, ash_drift = -8, vent_call = -8, alarm_mark = -20, pheromone = 12, survey_ping = 24, dark_pulse = 4, frost_trace = -12, spore_bloom = 28, pressure_tick = -8, radiant_heat = -16, tainted_sludge = 22, surge_line = 12, false_ping = 30, trade_mark = 26, pulse_mark = 16 },
  screecher = { track = 6, scratch = 8, scent_trail = 4, nest_debris = 10, wet_tracks = 8, ash_drift = 8, vent_call = 34, alarm_mark = 26, pheromone = -10, survey_ping = 18, dark_pulse = 4, frost_trace = 2, spore_bloom = 8, pressure_tick = 18, radiant_heat = 26, tainted_sludge = 4, smoke_veil = 18, false_ping = 24, pulse_mark = 14 },
  burrower = { track = 10, scratch = 18, scent_trail = 6, nest_debris = 24, wet_tracks = 30, ash_drift = -12, vent_call = 4, alarm_mark = 18, pheromone = 28, survey_ping = 4, dark_pulse = 2, frost_trace = -10, spore_bloom = 18, pressure_tick = 4, radiant_heat = -8, tainted_sludge = 34, surge_line = 36, trade_mark = 10 },
  mimic = { false_ping = 52, survey_ping = -44, trade_mark = 18, pulse_mark = 22, dark_pulse = 12 },
  warden = { alarm_mark = 36, pressure_tick = 30, trade_mark = 18, survey_ping = 10, false_ping = 12, pulse_mark = 20, scratch = 12 },
  leecher = { wet_tracks = 40, tainted_sludge = 38, surge_line = 32, scent_trail = 20, pheromone = 12, flare = -16, frost_trace = -8 },
  choir = { vent_call = 46, noisemaker = 42, alarm_mark = 28, radiant_heat = 22, smoke_veil = 26, false_ping = 24, survey_ping = 18, pulse_mark = 18 },
}

Creatures.biomeSpawns = {
  pressure_lab = { "warden", "screecher", "hunter" },
  waste_artery = { "leecher", "burrower", "skitter" },
  storm_drain = { "leecher", "burrower", "screecher", "hunter" },
  ash_foundry = { "choir", "screecher", "hunter", "stalker" },
  signal_catacombs = { "mimic", "choir", "screecher", "hunter" },
  bone_market = { "skitter", "warden", "hunter", "mimic" },
  organ_machine = { "mimic", "warden", "burrower", "stalker" },
}

return Creatures
