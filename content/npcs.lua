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
    topics = { "exit", "key", "threat", "tools" },
  },
  mechanic = {
    name = "Ivo",
    callsign = "MECH",
    title = "lock mechanic",
    speed = 0.92,
    radius = 0.17,
    height = 1.48,
    color = { 0.28, 0.26, 0.17, 0.88, 0.72, 0.38 },
    topics = { "key", "shelter", "tools", "threat" },
  },
  quartermaster = {
    name = "Sen",
    callsign = "QTR",
    title = "cache runner",
    speed = 1.0,
    radius = 0.16,
    height = 1.36,
    color = { 0.31, 0.18, 0.12, 0.92, 0.58, 0.28 },
    topics = { "key", "tools", "threat", "shelter" },
  },
  pathfinder = {
    name = "Kade",
    callsign = "PATH",
    title = "deck pathfinder",
    speed = 1.12,
    radius = 0.16,
    height = 1.5,
    color = { 0.18, 0.22, 0.34, 0.48, 0.68, 0.96 },
    topics = { "exit", "key", "threat", "shelter" },
  },
}

NPCs.creatureAdvice = {
  hunter = "Hunters follow noise and sight pressure. Break contact with turns, doors, noisemakers, scent, or pheromone edges.",
  stalker = "Stalkers work best in dark pockets. Flares, flash pods, and strong light make them give ground.",
  skitter = "Skitters steal supplies and panic loudly. Flash pods scatter them; bait or beacons can pull them off caches.",
  screecher = "Screechers chase repeated sound. Noisemakers and sonic stakes can move them, but they can pull worse things too.",
  burrower = "Burrowers own wet and broken ground. Pumps, valves, and grounding spikes make their territory less dangerous.",
  warden = "Wardens guard doors and key routes. Smoke, coolant, or breaker cuts buy time.",
  leecher = "Leechers follow live water. Grounding spikes and valves make flooded crossings safer.",
  mimic = "Mimics pretend to be useful signals or caches. Survey probes and caution near false pings expose them early.",
  choir = "Choirs ride vent sound. Flash pods, pheromones, and avoiding vent blooms reduce their pressure.",
  scavenger = "Scavengers steal exposed caches and loose tools. Lure beacons, bait, smoke, or snare wires can redirect them.",
}

NPCs.toolAdvice = {
  flare = "Flares reveal ground and push stalkers back, but they still advertise your position.",
  noisemaker = "Noisemakers move sound hunters. Place them away from your next route, not on top of it.",
  bait = "Bait redirects hungry creatures. Avoid dropping it next to nests unless you want a guard response.",
  scent = "Scent markers create false player trails for hunters and stalkers.",
  sonic = "Sonic stakes pull sound predators and can make creatures collide with each other.",
  flash = "Flash pods panic skitters and stalkers and briefly break sight pressure.",
  snare = "Snare wires slow the first creature that crosses them, then break loudly.",
  fuse = "Fuses make a loud burst that can pull threats away from a door or key.",
  seal = "Seal charges close a nearby route for a short window. Use them to split pursuit.",
  pheromone = "Pheromones create false territory edges that predators hesitate to cross.",
  breaker = "Breaker plugs force one nearby locked mechanism open briefly.",
  probe = "Survey probes reveal recent signs without showing exact creature positions.",
  oil = "Oil restores torch fuel. Spend it before entering long dark stretches.",
  valve = "Valve cranks calm flood pressure and nearby live wire routes.",
  ground = "Grounding spikes suppress nearby wires and repel leechers.",
  smoke = "Smoke breaks sight lines, but it can also carry noise through vents.",
  beacon = "Lure beacons create loud cache marks that pull scavengers and sound predators.",
  coolant = "Coolant suppresses embers and slows wardens or mimics caught nearby.",
}

NPCs.biomeAdvice = {
  cryo_vault = "Cryo vaults punish brittle routes and dark frost pockets. Breakers, flares, probes, oil, and coolant all matter here.",
  fungal_service = "Fungal service decks bend scent trails. Pheromones and scent tools are stronger, but spores can echo you.",
  pressure_lab = "Pressure labs turn doors and alarms into pathing problems. Breakers, seals, fuses, and flash pods are valuable.",
  reactor_trench = "Reactor trenches amplify heat and sound panic. Coolant, sonic stakes, fuses, and breakers give control.",
  waste_artery = "Waste arteries favor burrowers and live wires. Move fast, use bait, snares, valves, and grounding tools.",
  storm_drain = "Storm drains shift flood fronts and live conduits. Valves and grounding spikes are your cleanest answers.",
  ash_foundry = "Ash foundries hide sight in smoke and heat. Coolant, smoke, sonic stakes, and flares create route windows.",
  signal_catacombs = "Signal catacombs spoof caches and map marks. Probes expose lies before mimics wake.",
  bone_market = "Bone markets are scavenger territory. Beacons, bait, snares, and smoke help pull rivals off caches.",
  organ_machine = "Organ machines use living doors and pulse locks. Coolant, breakers, valves, pheromones, and grounding tools help.",
}

return NPCs
