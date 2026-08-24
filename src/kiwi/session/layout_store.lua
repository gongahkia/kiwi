local Json = require("kiwi.bench.json")
local ffi = require("ffi")

local Store = { maximum_bytes = 64 * 1024, schema_version = 2 }

ffi.cdef[[
int mkdir(const char* path, unsigned int mode);
int getpid(void);
]]

local function valid_integer(value, minimum, maximum)
  return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

local function exact_keys(value, allowed)
  if type(value) ~= "table" then return false end
  for key in pairs(value) do
    if not allowed[key] then return false end
  end
  return true
end

local function array(value)
  if type(value) ~= "table" then return false end
  for key in pairs(value) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then return false end
  end
  return true
end

local function validate_node(node, depth, pane_ids)
  if type(node) ~= "table" or depth > 64 then return nil end
  if node.kind == "leaf" then
    if not exact_keys(node, { kind = true, pane_id = true }) or not valid_integer(node.pane_id, 1, 4096) or pane_ids[node.pane_id] then return nil end
    pane_ids[node.pane_id] = true
    return 1
  end
  if not exact_keys(node, { kind = true, direction = true, ratio = true, first = true, second = true })
    or node.kind ~= "split" or (node.direction ~= "vertical" and node.direction ~= "horizontal")
    or type(node.ratio) ~= "number" or node.ratio < 0.1 or node.ratio > 0.9 then return nil end
  local first = validate_node(node.first, depth + 1, pane_ids)
  local second = first and validate_node(node.second, depth + 1, pane_ids)
  return first and second and first + second or nil
end

local function validate_snapshot(snapshot, schema_version)
  if not exact_keys(snapshot, { schema_version = true, windows = true }) or snapshot.schema_version ~= schema_version or not array(snapshot.windows) or #snapshot.windows < 1 or #snapshot.windows > 16 then
    return nil, "invalid-layout"
  end
  local window_ids = {}
  for _, window in ipairs(snapshot.windows) do
    local geometry = window.geometry
    local workspace = window.workspace
    local valid_window = schema_version == 1
      and exact_keys(window, { geometry = true, id = true, workspace = true }) and valid_integer(window.id, 1, 4096)
      or schema_version == Store.schema_version and exact_keys(window, { geometry = true, workspace = true })
    if not valid_window or (schema_version == 1 and window_ids[window.id]) or not exact_keys(geometry, { height = true, width = true, x = true, y = true })
      or not valid_integer(geometry.x, -32768, 32768) or not valid_integer(geometry.y, -32768, 32768)
      or not valid_integer(geometry.width, 320, 16384) or not valid_integer(geometry.height, 240, 16384)
      or not exact_keys(workspace, { active_tab_id = true, tabs = true }) or not valid_integer(workspace.active_tab_id, 1, 4096) or not array(workspace.tabs) or #workspace.tabs < 1 or #workspace.tabs > 32 then
      return nil, "invalid-layout"
    end
    if schema_version == 1 then window_ids[window.id] = true end
    local tab_ids = {}
    local pane_ids = {}
    local active_tab = false
    local pane_count = 0
    for _, tab in ipairs(workspace.tabs) do
      if not exact_keys(tab, { active_pane_id = true, id = true, pane_count = true, root = true }) or not valid_integer(tab.id, 1, 4096) or tab_ids[tab.id]
        or not valid_integer(tab.active_pane_id, 1, 4096) then return nil, "invalid-layout" end
      tab_ids[tab.id] = true
      if tab.id == workspace.active_tab_id then active_tab = true end
      local tab_pane_ids = {}
      local tab_panes = validate_node(tab.root, 0, tab_pane_ids)
      if tab_panes == nil or not tab_pane_ids[tab.active_pane_id] or (tab.pane_count ~= nil and tab.pane_count ~= tab_panes) then return nil, "invalid-layout" end
      for pane_id in pairs(tab_pane_ids) do
        if pane_ids[pane_id] then return nil, "invalid-layout" end
        pane_ids[pane_id] = true
      end
      pane_count = pane_count + tab_panes
    end
    if not active_tab or pane_count > 64 then return nil, "invalid-layout" end
  end
  return true
end

function Store.validate(snapshot)
  return validate_snapshot(snapshot, Store.schema_version)
end

function Store.migrate(snapshot)
  if type(snapshot) ~= "table" or type(snapshot.schema_version) ~= "number" or snapshot.schema_version % 1 ~= 0 then
    return nil, "invalid-layout"
  end
  if snapshot.schema_version == Store.schema_version then
    if not validate_snapshot(snapshot, Store.schema_version) then return nil, "invalid-layout" end
    return snapshot, false
  end
  if snapshot.schema_version ~= 1 then return nil, "unsupported-layout-version" end
  if not validate_snapshot(snapshot, 1) then return nil, "invalid-layout" end
  local windows = {}
  for index, window in ipairs(snapshot.windows) do
    -- v1 controller IDs are process-local and were never consumed by restore.
    -- v2 keeps only the ordered geometry/topology contract.
    windows[index] = { geometry = window.geometry, workspace = window.workspace }
  end
  local migrated = { schema_version = Store.schema_version, windows = windows }
  assert(validate_snapshot(migrated, Store.schema_version))
  return migrated, true
end

function Store.path(environment, platform)
  environment = environment or os.getenv
  platform = platform or ffi.os
  local home = environment("HOME") or "."
  if platform == "OSX" then return home .. "/Library/Application Support/io.github.gongahkia.kiwi/workspace-v2.json" end
  return (environment("XDG_STATE_HOME") or home .. "/.local/state") .. "/kiwi/workspace-v2.json"
end

function Store.legacy_path(environment, platform)
  environment = environment or os.getenv
  platform = platform or ffi.os
  local home = environment("HOME") or "."
  if platform == "OSX" then return home .. "/Library/Application Support/io.github.gongahkia.kiwi/workspace-v1.json" end
  return (environment("XDG_STATE_HOME") or home .. "/.local/state") .. "/kiwi/workspace-v1.json"
end

function Store.encode(snapshot)
  assert(Store.validate(snapshot))
  return Json.encode(snapshot)
end

local function utf8(codepoint)
  if codepoint < 0x80 then return string.char(codepoint) end
  if codepoint < 0x800 then return string.char(0xc0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40) end
  if codepoint < 0x10000 then return string.char(0xe0 + math.floor(codepoint / 0x1000), 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40) end
  return string.char(0xf0 + math.floor(codepoint / 0x40000), 0x80 + math.floor(codepoint / 0x1000) % 0x40, 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

local function decode(text)
  local index = 1
  local length = #text
  local function skip_space()
    while index <= length and text:sub(index, index):match("%s") do index = index + 1 end
  end
  local parse_value
  local function parse_string()
    assert(text:sub(index, index) == '"', "expected JSON string")
    index = index + 1
    local output = {}
    while index <= length do
      local byte = text:byte(index)
      if byte == 0x22 then
        index = index + 1
        return table.concat(output)
      end
      assert(byte >= 0x20, "JSON string contains a control byte")
      if byte ~= 0x5c then
        output[#output + 1] = string.char(byte)
        index = index + 1
      else
        index = index + 1
        local escape = text:sub(index, index)
        local simple = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if simple[escape] then
          output[#output + 1] = simple[escape]
          index = index + 1
        else
          assert(escape == "u", "JSON string has an invalid escape")
          local hex = text:sub(index + 1, index + 4)
          assert(#hex == 4 and hex:match("^[0-9a-fA-F]+$"), "JSON string has an invalid unicode escape")
          local codepoint = tonumber(hex, 16)
          index = index + 5
          if codepoint >= 0xd800 and codepoint <= 0xdbff then
            assert(text:sub(index, index + 1) == "\\u", "JSON string has an unpaired high surrogate")
            local low_hex = text:sub(index + 2, index + 5)
            assert(#low_hex == 4 and low_hex:match("^[0-9a-fA-F]+$") and tonumber(low_hex, 16) >= 0xdc00 and tonumber(low_hex, 16) <= 0xdfff, "JSON string has an invalid low surrogate")
            codepoint = 0x10000 + (codepoint - 0xd800) * 0x400 + (tonumber(low_hex, 16) - 0xdc00)
            index = index + 6
          else
            assert(codepoint < 0xdc00 or codepoint > 0xdfff, "JSON string has an unpaired low surrogate")
          end
          output[#output + 1] = utf8(codepoint)
        end
      end
    end
    error("unterminated JSON string")
  end
  local function parse_array(depth)
    index = index + 1
    skip_space()
    local output = {}
    if text:sub(index, index) == "]" then index = index + 1; return output end
    while true do
      output[#output + 1] = parse_value(depth + 1)
      skip_space()
      local separator = text:sub(index, index)
      if separator == "]" then index = index + 1; return output end
      assert(separator == ",", "JSON array needs a comma")
      index = index + 1
      skip_space()
    end
  end
  local function parse_object(depth)
    index = index + 1
    skip_space()
    local output = {}
    local seen = {}
    if text:sub(index, index) == "}" then index = index + 1; return output end
    while true do
      local key = parse_string()
      assert(not seen[key], "JSON object repeats a key")
      seen[key] = true
      skip_space()
      assert(text:sub(index, index) == ":", "JSON object needs a colon")
      index = index + 1
      skip_space()
      output[key] = parse_value(depth + 1)
      skip_space()
      local separator = text:sub(index, index)
      if separator == "}" then index = index + 1; return output end
      assert(separator == ",", "JSON object needs a comma")
      index = index + 1
      skip_space()
    end
  end
  parse_value = function(depth)
    assert(depth <= 128, "JSON nesting is too deep")
    skip_space()
    local start = text:sub(index, index)
    if start == '"' then return parse_string() end
    if start == "[" then return parse_array(depth) end
    if start == "{" then return parse_object(depth) end
    if text:sub(index, index + 3) == "true" then index = index + 4; return true end
    if text:sub(index, index + 4) == "false" then index = index + 5; return false end
    if text:sub(index, index + 3) == "null" then index = index + 4; return nil end
    local first = index
    if text:sub(index, index) == "-" then index = index + 1 end
    local digit = text:sub(index, index)
    if digit == "0" then
      index = index + 1
      assert(not text:sub(index, index):match("%d"), "JSON number has a leading zero")
    else
      assert(digit:match("[1-9]"), "invalid JSON value")
      repeat index = index + 1 until not text:sub(index, index):match("%d")
    end
    if text:sub(index, index) == "." then
      index = index + 1
      assert(text:sub(index, index):match("%d"), "JSON number has no fractional digits")
      repeat index = index + 1 until not text:sub(index, index):match("%d")
    end
    if text:sub(index, index):lower() == "e" then
      index = index + 1
      if text:sub(index, index) == "+" or text:sub(index, index) == "-" then index = index + 1 end
      assert(text:sub(index, index):match("%d"), "JSON number has no exponent digits")
      repeat index = index + 1 until not text:sub(index, index):match("%d")
    end
    local value = text:sub(first, index - 1)
    local number = tonumber(value)
    assert(number and number == number and number ~= math.huge and number ~= -math.huge, "JSON number is invalid")
    return number
  end
  local value = parse_value(0)
  skip_space()
  assert(index > length, "JSON has trailing data")
  return value
end

local function make_directories(path)
  local directory = path:match("^(.+)/[^/]+$")
  if directory == nil or directory == "" then return true end
  local current = directory:sub(1, 1) == "/" and "/" or ""
  for component in directory:gmatch("[^/]+") do
    current = current == "/" and current .. component or current == "" and component or current .. "/" .. component
    if ffi.C.mkdir(current, 448) ~= 0 and ffi.errno() ~= 17 then return nil, "could not create layout directory" end
  end
  return true
end

function Store.load(path)
  assert(type(path) == "string" and #path > 0, "layout path must be a non-empty string")
  local file = io.open(path, "rb")
  if file == nil then return nil, ffi.errno() == 2 and "missing" or "unavailable" end
  local text = file:read(Store.maximum_bytes + 1)
  file:close()
  if text == nil or #text > Store.maximum_bytes then return nil, "invalid-layout" end
  local decoded, decoded_or_error = pcall(decode, text)
  if not decoded then return nil, "invalid-layout" end
  local migrated, migration_or_reason = Store.migrate(decoded_or_error)
  if migrated == nil then return nil, migration_or_reason end
  return migrated, nil, migration_or_reason
end

function Store.write(path, snapshot)
  assert(type(path) == "string" and #path > 0, "layout path must be a non-empty string")
  if not Store.validate(snapshot) then return nil, "invalid-layout" end
  local directories, directory_reason = make_directories(path)
  if not directories then return nil, directory_reason end
  local temporary = path .. ".tmp-" .. tostring(ffi.C.getpid())
  local file = io.open(temporary, "wb")
  if file == nil then return nil, "could not create temporary layout" end
  local written = file:write(Store.encode(snapshot))
  local closed = file:close()
  if not written or not closed then
    os.remove(temporary)
    return nil, "could not write layout"
  end
  if not os.rename(temporary, path) then
    os.remove(temporary)
    return nil, "could not replace layout"
  end
  return true
end

return Store
