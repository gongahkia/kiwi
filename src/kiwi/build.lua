local Build = {}

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local value = file:read("*l")
  file:close()
  return value
end

local function metadata_value(root, name, fallback, read)
  local value = read(root .. "/" .. name)
  if value == nil or #value == 0 then return fallback end
  return value
end

function Build.info(options)
  options = options or {}
  local getenv = options.getenv or os.getenv
  local root = options.root or getenv("KIWI_ROOT") or "."
  local read = options.read or read_file
  return {
    release_mode = getenv("KIWI_RELEASE") == "1",
    revision = metadata_value(root, "BUILD_REVISION", "source", read),
    version = assert(metadata_value(root, "VERSION", nil, read), "VERSION is missing or empty"),
  }
end

function Build.format(info)
  return string.format("Kiwi %s (revision %s, mode %s)", info.version, info.revision, info.release_mode and "release" or "development")
end

return Build
