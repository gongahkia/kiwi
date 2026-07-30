local required_markers = {
  "content/missions/.gitkeep",
  "content/operatives/.gitkeep",
  "content/equipment/.gitkeep",
  "content/doctrines/.gitkeep",
  "content/localisation/.gitkeep",
}

local missing = {}
for _, marker in ipairs(required_markers) do
  local file = io.open(marker, "r")
  if file then
    file:close()
  else
    missing[#missing + 1] = marker
  end
end

if #missing > 0 then
  io.stderr:write("missing content skeleton markers: " .. table.concat(missing, ", ") .. "\n")
  os.exit(1)
end

io.write("CONTENT_VALID\n")
