local Upgrades = {}

Upgrades.defs = {
  fleet_soles = {
    label = "Fleet Soles",
    summary = "+8% walk speed, +6% sprint speed.",
    max = 2,
  },
  deep_pockets = {
    label = "Deep Pockets",
    summary = "+1 max charge for each field tool. Start each deck stocked higher.",
    max = 2,
  },
  cool_burn = {
    label = "Cool Burn",
    summary = "Torch and hazard drain are reduced. Oil also extends nearby flares.",
    max = 2,
  },
  flare_survey = {
    label = "White Flare",
    summary = "Flares create a short survey pulse and expose nearby trail signs.",
    max = 1,
  },
  echo_snare = {
    label = "Echo Wire",
    summary = "Noisemakers refresh nearby snares and make them lure harder.",
    max = 1,
  },
  adrenal_step = {
    label = "Adrenal Step",
    summary = "Move faster during the final 12 seconds of a deck.",
    max = 1,
  },
  cache_hunter = {
    label = "Cache Hunter",
    summary = "Survey probes reveal mimics and mark nearby tool caches.",
    max = 1,
  },
  beacon_pack = {
    label = "Beacon Pack",
    summary = "Beacons last longer and pull skitters, screechers, and choir harder.",
    max = 1,
  },
  scent_lattice = {
    label = "Scent Lattice",
    summary = "Scent markers chain extra false trail signs through the room.",
    max = 1,
  },
}

Upgrades.order = {
  "deep_pockets",
  "cool_burn",
  "flare_survey",
  "cache_hunter",
}

function Upgrades.count(runUpgrades, id)
  return runUpgrades and (runUpgrades[id] or 0) or 0
end

function Upgrades.has(runUpgrades, id)
  return Upgrades.count(runUpgrades, id) > 0
end

function Upgrades.available(runUpgrades)
  local available = {}

  for _, id in ipairs(Upgrades.order) do
    local def = Upgrades.defs[id]
    if def and Upgrades.count(runUpgrades, id) < (def.max or 1) then
      available[#available + 1] = id
    end
  end

  return available
end

return Upgrades
