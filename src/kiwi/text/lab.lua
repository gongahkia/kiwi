local Lab = {
  max_backends = 4,
}

local function backend_name(value)
  assert(type(value) == "string" and #value > 0 and #value <= 64 and value:match("^[a-z0-9][a-z0-9_-]*$") ~= nil,
    "text laboratory backend names must use lowercase letters, digits, hyphens, or underscores and be at most 64 bytes")
  return value
end

function Lab.requested_backend(getenv)
  getenv = getenv or os.getenv
  if getenv("KIWI_TEXT_LAB") ~= "1" then return "atlas" end
  return backend_name(getenv("KIWI_TEXT_LAB_BACKEND") or "atlas")
end

function Lab.parse_backends(value)
  if value == nil or #value == 0 then return { "atlas" } end
  assert(value:sub(1, 1) ~= "," and value:sub(-1) ~= "," and not value:find(",,", 1, true),
    "KIWI_TEXT_LAB_BACKENDS must be a comma-separated backend list without empty entries")
  local names = {}
  local seen = {}
  for item in value:gmatch("[^,]+") do
    item = backend_name(item)
    assert(not seen[item], "KIWI_TEXT_LAB_BACKENDS must not repeat " .. item)
    seen[item] = true
    names[#names + 1] = item
    assert(#names <= Lab.max_backends, "KIWI_TEXT_LAB_BACKENDS supports at most " .. Lab.max_backends .. " backends")
  end
  return names
end

function Lab.with_baseline(names)
  local result = { "atlas" }
  for _, name in ipairs(names) do
    if name ~= "atlas" then result[#result + 1] = name end
  end
  return result
end

return Lab
