local NPCs = {}

NPCs.order = { "scout", "mechanic", "quartermaster", "pathfinder" }

NPCs.profiles = {
  scout = {
    name = "Mara",
    callsign = "SCOUT",
    title = "route scout",
    speed = 1.05,
    radius = 0.16,
    height = 1.42,
    color = { 0.18, 0.36, 0.34, 0.58, 0.92, 0.78 },
    topics = { "route", "exit", "threat", "cycle", "biome", "key", "shelter", "tools" },
  },
  mechanic = {
    name = "Ivo",
    callsign = "MECH",
    title = "lock mechanic",
    speed = 0.92,
    radius = 0.17,
    height = 1.48,
    color = { 0.28, 0.26, 0.17, 0.88, 0.72, 0.38 },
    topics = { "systems", "hazards", "key", "shelter", "tools", "cycle", "threat", "route" },
  },
  quartermaster = {
    name = "Sen",
    callsign = "QTR",
    title = "cache runner",
    speed = 1.0,
    radius = 0.16,
    height = 1.36,
    color = { 0.31, 0.18, 0.12, 0.92, 0.58, 0.28 },
    topics = { "cache", "tools", "faction", "key", "threat", "hazards", "shelter", "route" },
  },
  pathfinder = {
    name = "Kade",
    callsign = "PATH",
    title = "deck pathfinder",
    speed = 1.12,
    radius = 0.16,
    height = 1.5,
    color = { 0.18, 0.22, 0.34, 0.48, 0.68, 0.96 },
    topics = { "route", "shelter", "exit", "key", "biome", "cycle", "threat", "systems" },
  },
}

NPCs.creatureAdvice = {
  hunter = "Hunters follow noise and sight pressure. Break contact with turns, doors, darkness, and noisemakers placed away from your route.",
  stalker = "Stalkers work best in dark pockets. Flares and strong light make them give ground.",
  mimic = "Mimics pretend to be useful signals or caches. Survey probes and caution near false pings expose them early.",
}

NPCs.toolAdvice = {
  flare = "Flares buy a small island of readable ground and push stalkers back, but the noise and light can still draw attention.",
  noisemaker = "Noisemakers move sound hunters. Place them across an alternate route, not on top of your next step.",
  probe = "Survey probes reveal recent signs, cache lies, and route pressure without giving you exact creature positions.",
  oil = "Oil restores torch fuel. Spend it before entering long dark stretches.",
}

NPCs.biomeAdvice = {
  cryo_vault = "Cryo vaults punish brittle routes and dark frost pockets. Flares, probes, and oil matter more than speed.",
  fungal_service = "Fungal service decks bend trail reads. Trust light, probe suspicious marks, and avoid noisy shortcuts.",
  pressure_lab = "Pressure labs turn doors and alarms into pathing problems. Probes and noisemakers help you read and redirect pressure.",
  reactor_trench = "Reactor trenches amplify sound panic. Flares, noisemakers, probes, and oil keep the route readable.",
  waste_artery = "Waste arteries make movement loud and ugly. Move cleanly, save oil, and probe before crossing blind rooms.",
  storm_drain = "Storm drains shift flood fronts and live conduits. Probes and careful routing are your cleanest answers.",
  ash_foundry = "Ash foundries hide sight in ash and heat. Flares, noisemakers, probes, and oil create route windows.",
  signal_catacombs = "Signal catacombs spoof caches and map marks. Probes expose lies before mimics wake.",
  bone_market = "Bone markets hide pressure behind cache marks. Probe first and keep a noisemaker for the way out.",
  organ_machine = "Organ machines use living doors and pulse locks. Probes, flares, and oil keep routes legible.",
}

return NPCs
