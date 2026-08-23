local Doctor = require("kiwi.doctor")
local Json = require("kiwi.bench.json")

local Qualification = {
  schema_version = 1,
  maximum_checks = 16,
  maximum_name_bytes = 64,
  maximum_detail_bytes = 256,
}

local statuses = {
  failed = true,
  manual = true,
  passed = true,
  skipped = true,
}

local function bounded(value, maximum)
  value = tostring(value or "")
  if #value <= maximum then return value end
  local suffix = " [truncated]"
  return value:sub(1, maximum - #suffix) .. suffix
end

local function check_copy(check)
  assert(type(check) == "table", "compatibility qualification check must be a table")
  local name = bounded(check.name, Qualification.maximum_name_bytes)
  local status = check.status
  assert(name:match("^[a-z0-9][a-z0-9%-]*$") ~= nil, "compatibility qualification check name must use lowercase hyphenated ASCII")
  assert(statuses[status] == true, "compatibility qualification check status is invalid")
  return {
    detail = bounded(check.detail, Qualification.maximum_detail_bytes),
    name = name,
    status = status,
  }
end

local function privacy_copy(privacy, checks)
  local copied = {}
  for key, value in pairs(privacy or {}) do copied[key] = value end
  copied.network = "not used"
  for _, check in ipairs(checks) do
    if check.name == "ssh" and check.status ~= "skipped" then
      copied.network = "controlled SSH terminfo probe; host excluded"
      break
    end
  end
  return copied
end

function Qualification.collect(checks, options)
  options = options or {}
  assert(type(checks) == "table" and #checks <= Qualification.maximum_checks, "compatibility qualification check count exceeds the fixed limit")
  local doctor = options.doctor or Doctor.collect(options)
  local copied = {}
  for index, check in ipairs(checks) do copied[index] = check_copy(check) end
  return {
    checks = copied,
    environment = doctor.environment,
    gpu = doctor.gpu,
    kind = "kiwi-daily-driver-compatibility",
    privacy = privacy_copy(doctor.privacy, copied),
    schema_version = Qualification.schema_version,
  }
end

function Qualification.encode(report)
  return Json.encode(report)
end

function Qualification.read_checks(path)
  local file, message = io.open(path, "rb")
  assert(file, "unable to read compatibility qualification input: " .. tostring(message))
  local checks = {}
  local line_number = 0
  for line in file:lines() do
    line_number = line_number + 1
    local name, status, detail = line:match("^([^\t]+)\t([^\t]+)\t(.*)$")
    assert(name ~= nil, "invalid compatibility qualification input on line " .. line_number)
    checks[#checks + 1] = { name = name, status = status, detail = detail }
  end
  file:close()
  return checks
end

function Qualification.write(path, report)
  local file, message = io.open(path, "wb")
  assert(file, "unable to write compatibility qualification report: " .. tostring(message))
  file:write(Qualification.encode(report), "\n")
  file:close()
end

local function parse_options(arguments)
  local options = {}
  local index = 1
  while index <= #arguments do
    local value = arguments[index]
    if value == "--input" then
      index = index + 1
      options.input = assert(arguments[index], "--input needs a path")
    elseif value == "--output" then
      index = index + 1
      options.output = assert(arguments[index], "--output needs a path")
    else
      error("unknown compatibility qualification option: " .. value .. "; use --input PATH --output PATH")
    end
    index = index + 1
  end
  assert(options.input ~= nil and options.output ~= nil, "--input PATH and --output PATH are required")
  return options
end

function Qualification.main(arguments)
  local options = parse_options(arguments or arg)
  Qualification.write(options.output, Qualification.collect(Qualification.read_checks(options.input)))
end

if ... ~= "kiwi.compatibility.qualification" then Qualification.main(arg) end

return Qualification
