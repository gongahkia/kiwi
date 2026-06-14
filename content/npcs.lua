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
  hunter = "Hunters follow noise and sight pressure. Break contact with turns, noisemakers, scent, or pheromone edges.",
  stalker = "Stalkers work best in dark pockets. Flares and strong light make them give ground.",
  skitter = "Skitters steal supplies and panic loudly. Beacons, scent, or snares can pull them off caches.",
  screecher = "Screechers chase repeated sound. Noisemakers and beacons can move them, but they can pull worse things too.",
  burrower = "Burrowers own wet and broken ground. Pheromones and careful routing keep them off your line.",
  mimic = "Mimics pretend to be useful signals or caches. Survey probes and caution near false pings expose them early.",
  warden = "Wardens patrol locks, gates, and machinery. Snares, probes, and route changes buy the best window.",
  leecher = "Leechers surge through wet, sludge, and tar lanes. Flares and dry routes make them easier to shake.",
  choir = "Choir packs follow rhythm and repeated noise. Beacons move them hard, but they can wake the whole deck.",
}

NPCs.toolAdvice = {
  flare = "Flares reveal ground and push stalkers back, but they still advertise your position.",
  noisemaker = "Noisemakers move sound hunters. Place them away from your next route, not on top of it.",
  scent = "Scent markers create false player trails for hunters and stalkers.",
  snare = "Snare wires slow the first creature that crosses them, then break loudly.",
  pheromone = "Pheromones create false territory edges that predators hesitate to cross.",
  probe = "Survey probes reveal recent signs without showing exact creature positions.",
  oil = "Oil restores torch fuel. Spend it before entering long dark stretches.",
  beacon = "Lure beacons create loud cache marks that pull skitters, screechers, choir packs, and curious hunters.",
}

NPCs.biomeAdvice = {
  cryo_vault = "Cryo vaults punish brittle routes and dark frost pockets. Flares, probes, oil, and snares all matter here.",
  fungal_service = "Fungal service decks bend scent trails. Pheromones and scent tools are stronger, but spores can echo you.",
  pressure_lab = "Pressure labs turn doors and alarms into pathing problems. Probes, snares, and noisemakers help you read and redirect pressure.",
  reactor_trench = "Reactor trenches amplify heat and sound panic. Flares, noisemakers, probes, and oil keep the route readable.",
  waste_artery = "Waste arteries favor burrowers and live wires. Move cleanly, use scent, snares, pheromones, and probes.",
  storm_drain = "Storm drains shift flood fronts and live conduits. Probes and careful routing are your cleanest answers.",
  ash_foundry = "Ash foundries hide sight in ash and heat. Flares, noisemakers, probes, and oil create route windows.",
  signal_catacombs = "Signal catacombs spoof caches and map marks. Probes expose lies before mimics wake.",
  bone_market = "Bone markets are theft territory. Beacons, scent, snares, and probes help pull pressure off caches.",
  organ_machine = "Organ machines use living doors and pulse locks. Pheromones, probes, snares, flares, and oil help.",
}

return NPCs
