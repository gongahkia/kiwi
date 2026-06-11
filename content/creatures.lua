local Creatures = {}

Creatures.defs = {
  hunter = { radius = 0.2, baseSpeed = 1.18, sightSpeed = 1.68, sight = 24, hearing = 10, aggression = 1, height = 1.55, lethal = true },
  stalker = { radius = 0.18, baseSpeed = 1.02, sightSpeed = 1.92, sight = 18, hearing = 7, aggression = 0.72, height = 1.35, lethal = true },
  skitter = { radius = 0.14, baseSpeed = 1.34, sightSpeed = 1.72, sight = 12, hearing = 9, aggression = 0.1, height = 0.55, lethal = false },
  screecher = { radius = 0.18, baseSpeed = 0.95, sightSpeed = 1.52, sight = 6, hearing = 18, aggression = 0.86, height = 1.18, lethal = true },
  burrower = { radius = 0.22, baseSpeed = 0.78, sightSpeed = 1.18, sight = 10, hearing = 8, aggression = 0.62, height = 0.85, lethal = true },
  warden = { radius = 0.24, baseSpeed = 0.72, sightSpeed = 1.24, sight = 15, hearing = 8, aggression = 0.92, height = 1.8, lethal = true, guard = true },
  leecher = { radius = 0.16, baseSpeed = 0.92, sightSpeed = 1.48, sight = 8, hearing = 12, aggression = 0.68, height = 0.46, lethal = true, aquatic = true },
  mimic = { radius = 0.17, baseSpeed = 0.38, sightSpeed = 1.7, sight = 10, hearing = 5, aggression = 0.8, height = 0.62, lethal = true, dormant = true },
  choir = { radius = 0.19, baseSpeed = 0.88, sightSpeed = 1.45, sight = 7, hearing = 20, aggression = 0.76, height = 1.1, lethal = true, flock = true },
  scavenger = { radius = 0.17, baseSpeed = 1.18, sightSpeed = 1.46, sight = 13, hearing = 11, aggression = 0.24, height = 0.9, lethal = false, thief = true },
}

Creatures.predatorRank = {
  skitter = 0,
  scavenger = 1,
  leecher = 1,
  stalker = 1,
  screecher = 2,
  choir = 2,
  burrower = 2,
  mimic = 2,
  warden = 3,
  hunter = 3,
}

Creatures.toolAffinity = {
  hunter = { bait = 24, scent = 34, sonic = 18, noisemaker = 22, flare = 10, pheromone = -38, probe = 8, smoke = -8, beacon = 18 },
  stalker = { bait = 14, scent = 28, sonic = 10, noisemaker = 15, flare = -55, flash = -60, pheromone = -30, probe = 12, smoke = 22, coolant = -16 },
  skitter = { bait = 36, scent = 18, sonic = 18, noisemaker = 10, flash = -60, pheromone = 14, probe = 32, beacon = 20 },
  screecher = { bait = 8, scent = 8, sonic = 58, noisemaker = 44, flare = 8, pheromone = -8, probe = 20, smoke = 18 },
  burrower = { bait = 18, scent = 10, sonic = 8, noisemaker = 12, pheromone = 30, probe = 4, ground = -24, valve = 12 },
  warden = { beacon = 44, fuse = 20, breaker = 18, noisemaker = 6, smoke = -28, coolant = -18, flare = 8 },
  leecher = { bait = 18, valve = 34, ground = -40, noisemaker = 14, pheromone = 10, smoke = 4 },
  mimic = { probe = -48, flare = -20, beacon = 22, noisemaker = 14, scent = 10 },
  choir = { sonic = 64, noisemaker = 52, beacon = 30, smoke = 26, flash = -35, pheromone = -12 },
  scavenger = { bait = 20, beacon = 38, probe = 24, smoke = 16, flare = 12, snare = -18 },
}

Creatures.signalAffinity = {
  hunter = { track = 28, scratch = 22, scent_trail = 30, nest_debris = 14, wet_tracks = 8, ash_drift = -4, vent_call = 14, alarm_mark = 22, pheromone = -34, survey_ping = 8, dark_pulse = 10, frost_trace = 8, spore_bloom = 20, pressure_tick = 18, radiant_heat = 6, tainted_sludge = 12, surge_line = 10, smoke_veil = -4, false_ping = 16, trade_mark = 18, pulse_mark = 16 },
  stalker = { track = 24, scratch = 30, scent_trail = 26, nest_debris = 8, wet_tracks = 4, ash_drift = 4, vent_call = 8, alarm_mark = 18, pheromone = -28, survey_ping = 12, dark_pulse = 36, frost_trace = 24, spore_bloom = 12, pressure_tick = 14, radiant_heat = -6, tainted_sludge = 4, surge_line = 6, smoke_veil = 24, false_ping = 18, trade_mark = 10, pulse_mark = 12 },
  skitter = { track = -16, scratch = -18, scent_trail = 12, nest_debris = 32, wet_tracks = 8, ash_drift = -8, vent_call = -8, alarm_mark = -20, pheromone = 12, survey_ping = 24, dark_pulse = 4, frost_trace = -12, spore_bloom = 28, pressure_tick = -8, radiant_heat = -16, tainted_sludge = 22, surge_line = 12, false_ping = 30, trade_mark = 26, pulse_mark = 16 },
  screecher = { track = 6, scratch = 8, scent_trail = 4, nest_debris = 10, wet_tracks = 8, ash_drift = 8, vent_call = 34, alarm_mark = 26, pheromone = -10, survey_ping = 18, dark_pulse = 4, frost_trace = 2, spore_bloom = 8, pressure_tick = 18, radiant_heat = 26, tainted_sludge = 4, smoke_veil = 18, false_ping = 24, pulse_mark = 14 },
  burrower = { track = 10, scratch = 18, scent_trail = 6, nest_debris = 24, wet_tracks = 30, ash_drift = -12, vent_call = 4, alarm_mark = 18, pheromone = 28, survey_ping = 4, dark_pulse = 2, frost_trace = -10, spore_bloom = 18, pressure_tick = 4, radiant_heat = -8, tainted_sludge = 34, surge_line = 36, trade_mark = 10 },
  warden = { pressure_tick = 38, pulse_mark = 34, alarm_mark = 30, false_ping = 22, survey_ping = 18, vent_call = 8, trade_mark = 14 },
  leecher = { wet_tracks = 42, surge_line = 46, tainted_sludge = 34, pheromone = 12, alarm_mark = 14, pulse_mark = 10 },
  mimic = { false_ping = 52, survey_ping = -44, trade_mark = 18, pulse_mark = 22, dark_pulse = 12 },
  choir = { vent_call = 48, sonic = 36, false_ping = 28, alarm_mark = 24, smoke_veil = 20, dark_pulse = 18 },
  scavenger = { trade_mark = 42, false_ping = 28, survey_ping = 30, nest_debris = 22, alarm_mark = -18, salvage = 40 },
}

Creatures.biomeSpawns = {
  storm_drain = { "leecher", "burrower", "screecher" },
  ash_foundry = { "choir", "screecher", "hunter" },
  signal_catacombs = { "mimic", "warden", "choir" },
  bone_market = { "scavenger", "skitter", "hunter" },
  organ_machine = { "warden", "leecher", "mimic" },
}

return Creatures
