package.path = "./?.lua;./?/init.lua;" .. package.path

local parser = require("src.dsl.parser")
local source_loader = require("src.dsl.source_loader")

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

local source, source_error = source_loader.load(source_loader.DEFAULT_FIXTURE, function(path)
  local file, err = io.open(path, "rb")
  if not file then
    return nil, err
  end
  local contents = file:read("*a")
  file:close()
  return contents
end)
if not source then
  io.stderr:write(source_error.code .. ": " .. source_error.message .. "\n")
  os.exit(1)
end

local _, diagnostics = parser.parse(source)
if #diagnostics > 0 then
  io.stderr:write("invalid initial doctrine fixture\n")
  os.exit(1)
end

io.write("CONTENT_VALID\n")
