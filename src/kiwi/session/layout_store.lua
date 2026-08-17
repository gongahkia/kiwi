local Json = require("kiwi.bench.json")

local Store = { maximum_bytes = 64 * 1024, schema_version = 1 }

local function valid_integer(value, minimum, maximum)
  return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

local function validate_node(node, depth, count)
  if type(node) ~= "table" or depth > 64 then return nil end
  if node.kind == "leaf" then return valid_integer(node.pane_id, 1, 4096) and count + 1 or nil end
  if node.kind ~= "split" or (node.direction ~= "vertical" and node.direction ~= "horizontal")
    or type(node.ratio) ~= "number" or node.ratio < 0.1 or node.ratio > 0.9 then return nil end
  local first = validate_node(node.first, depth + 1, count)
  return first and validate_node(node.second, depth + 1, first) or nil
end

function Store.validate(snapshot)
  if type(snapshot) ~= "table" or snapshot.schema_version ~= Store.schema_version or type(snapshot.windows) ~= "table" or #snapshot.windows > 16 then
    return nil, "invalid-layout"
  end
  for _, window in ipairs(snapshot.windows) do
    local geometry = window.geometry
    local workspace = window.workspace
    if type(window) ~= "table" or not valid_integer(window.id, 1, 4096) or type(geometry) ~= "table"
      or not valid_integer(geometry.x, -32768, 32768) or not valid_integer(geometry.y, -32768, 32768)
      or not valid_integer(geometry.width, 320, 16384) or not valid_integer(geometry.height, 240, 16384)
      or type(workspace) ~= "table" or type(workspace.tabs) ~= "table" or #workspace.tabs > 32 then
      return nil, "invalid-layout"
    end
    for _, tab in ipairs(workspace.tabs) do
      if type(tab) ~= "table" or not valid_integer(tab.id, 1, 4096) or not valid_integer(tab.active_pane_id, 1, 4096)
        or not validate_node(tab.root, 0, 0) then return nil, "invalid-layout" end
    end
  end
  return true
end

function Store.path(environment, platform)
  environment = environment or os.getenv
  local home = environment("HOME") or "."
  if platform == "OSX" then return home .. "/Library/Application Support/io.github.gongahkia.kiwi/workspace-v1.json" end
  return (environment("XDG_STATE_HOME") or home .. "/.local/state") .. "/kiwi/workspace-v1.json"
end

function Store.encode(snapshot)
  assert(Store.validate(snapshot))
  return Json.encode(snapshot)
end

return Store
