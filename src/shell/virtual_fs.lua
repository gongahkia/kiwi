local Errors = require("runtime.errors")
local Path = require("shell.vfs_path")

local VirtualFS = {}
local fs_mt = {}
fs_mt.__index = fs_mt

VirtualFS.contract = {
  append_file = "append_file(path, bytes) -> true | nil, error",
  change_directory = "change_directory(path) -> true | nil, error",
  constructor = "new(options?) -> virtual_filesystem | nil, error",
  get_cwd = "get_cwd() -> canonical_path | nil, error",
  list = "list(path, options?) -> byte_string[] | nil, error",
  make_directory = "make_directory(path) -> true | nil, error",
  read_file = "read_file(path, options?) -> byte_string | nil, error",
  remove = "remove(path) -> true | nil, error",
  rename = "rename(source, destination) -> true | nil, error",
  stat = "stat(path) -> virtual_filesystem_node | nil, error",
  status = "status() -> virtual_filesystem_status",
  write_file = "write_file(path, bytes) -> true | nil, error",
}

local default_limits = {
  max_canonical_path_bytes = 4096,
  max_component_bytes = 255,
  max_directories = 512,
  max_directory_entries = 256,
  max_file_bytes = 16384,
  max_files = 512,
  max_initial_tree_depth = 32,
  max_nodes = 1024,
  max_path_bytes = 4096,
  max_path_components = 64,
  max_returned_bytes = 16384,
  max_returned_directory_entries = 128,
  max_total_file_bytes = 65536,
}

local allowed_limits = {}
for name in pairs(default_limits) do
  allowed_limits[name] = true
end

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function copy_string(value)
  return value:sub(1, #value)
end

local function copy_components(components)
  local result = {}
  for index, component in ipairs(components) do
    result[index] = copy_string(component)
  end
  return result
end

local function byte_less(left, right)
  local length = math.min(#left, #right)
  for index = 1, length do
    local left_byte = left:byte(index)
    local right_byte = right:byte(index)
    if left_byte ~= right_byte then
      return left_byte < right_byte
    end
  end
  return #left < #right
end

local function sorted_keys(value)
  local result = {}
  for key in pairs(value) do
    result[#result + 1] = key
  end
  table.sort(result, byte_less)
  return result
end

local function positive_integer(value, name, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > maximum then
    return command_error(name .. " must be an integer within the supported bound", {
      limit = maximum,
      minimum = 1,
      provided = value,
      reason = "resource_limit",
    })
  end
  return value
end

local function normalise_limits(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return command_error("virtual filesystem limits must be a table", { reason = "resource_limit" })
  end
  for name in pairs(value) do
    if not allowed_limits[name] then
      return command_error("virtual filesystem limit is unsupported", {
        limit = name,
        reason = "resource_limit",
      })
    end
  end
  local result = {}
  for name, default in pairs(default_limits) do
    local limit_value, limit_error = positive_integer(value[name] or default, name, default)
    if not limit_value then
      return nil, limit_error
    end
    result[name] = limit_value
  end
  if result.max_directories < 1 or result.max_nodes < 1 then
    return command_error("virtual filesystem limits cannot exclude the root directory", {
      reason = "resource_limit",
    })
  end
  return result
end

local function path_limits(limits)
  return {
    max_canonical_path_bytes = limits.max_canonical_path_bytes,
    max_component_bytes = limits.max_component_bytes,
    max_path_bytes = limits.max_path_bytes,
    max_path_components = limits.max_path_components,
  }
end

local function valid_name(value, limits)
  if type(value) ~= "string" or #value == 0 or value == "." or value == ".." then
    return command_error("virtual filesystem name is invalid", { reason = "invalid_path_byte" })
  end
  if #value > limits.max_component_bytes then
    return command_error("virtual filesystem name exceeds its byte limit", {
      limit = limits.max_component_bytes,
      reason = "component_too_large",
    })
  end
  if value:find("/", 1, true) or value:find("\0", 1, true) then
    return command_error("virtual filesystem name contains a reserved byte", {
      reason = "invalid_path_byte",
    })
  end
  return value
end

local function new_directory(parent, name)
  return { children = {}, child_count = 0, kind = "directory", name = name, parent = parent }
end

local function new_file(parent, name, data)
  return { data = copy_string(data), kind = "file", name = name, parent = parent }
end

local function status_copy(fs)
  return {
    cwd = Path.render(fs.cwd_components),
    destroyed = fs.destroyed,
    directories = fs.directories,
    files = fs.files,
    nodes = fs.nodes,
    retained_file_bytes = fs.retained_file_bytes,
  }
end

local function check_live(fs)
  if fs.destroyed then
    return command_error("virtual filesystem is destroyed", { reason = "filesystem_closed" })
  end
  return true
end

local function check_increment(current, increment, maximum, reason, message)
  if increment > maximum - current then
    return command_error(message, { limit = maximum, reason = reason })
  end
  return true
end

local function add_node(fs, kind, byte_count)
  local okay, node_error = check_increment(
    fs.nodes,
    1,
    fs.limits.max_nodes,
    "filesystem_full",
    "virtual filesystem node limit is reached"
  )
  if not okay then
    return nil, node_error
  end
  if kind == "directory" then
    local directory_okay, directory_error = check_increment(
      fs.directories,
      1,
      fs.limits.max_directories,
      "filesystem_full",
      "virtual filesystem directory limit is reached"
    )
    if not directory_okay then
      return nil, directory_error
    end
  else
    local file_okay, file_error = check_increment(
      fs.files,
      1,
      fs.limits.max_files,
      "filesystem_full",
      "virtual filesystem file limit is reached"
    )
    if not file_okay then
      return nil, file_error
    end
    local bytes_okay, bytes_error = check_increment(
      fs.retained_file_bytes,
      byte_count,
      fs.limits.max_total_file_bytes,
      "filesystem_full",
      "virtual filesystem byte limit is reached"
    )
    if not bytes_okay then
      return nil, bytes_error
    end
  end
  fs.nodes = fs.nodes + 1
  if kind == "directory" then
    fs.directories = fs.directories + 1
  else
    fs.files = fs.files + 1
    fs.retained_file_bytes = fs.retained_file_bytes + byte_count
  end
  return true
end

local function copy_initial_node(fs, description, parent, name, depth, seen)
  if type(description) ~= "table" or seen[description] then
    return command_error(
      "virtual filesystem initial tree node is invalid",
      { reason = "resource_limit" }
    )
  end
  seen[description] = true
  if depth > fs.limits.max_initial_tree_depth then
    return command_error("virtual filesystem initial tree exceeds its depth limit", {
      limit = fs.limits.max_initial_tree_depth,
      reason = "resource_limit",
    })
  end
  if description.kind == "file" then
    for field in pairs(description) do
      if field ~= "data" and field ~= "kind" then
        return command_error(
          "virtual filesystem file description is invalid",
          { reason = "resource_limit" }
        )
      end
    end
    if type(description.data) ~= "string" then
      return command_error(
        "virtual filesystem file data must be a byte string",
        { reason = "resource_limit" }
      )
    end
    if #description.data > fs.limits.max_file_bytes then
      return command_error("virtual filesystem file exceeds its byte limit", {
        limit = fs.limits.max_file_bytes,
        reason = "file_too_large",
      })
    end
    local okay, capacity_error = add_node(fs, "file", #description.data)
    if not okay then
      return nil, capacity_error
    end
    return new_file(parent, name, description.data)
  end
  if description.kind ~= "directory" then
    return command_error(
      "virtual filesystem node kind is unsupported",
      { reason = "resource_limit" }
    )
  end
  for field in pairs(description) do
    if field ~= "entries" and field ~= "kind" then
      return command_error(
        "virtual filesystem directory description is invalid",
        { reason = "resource_limit" }
      )
    end
  end
  if type(description.entries) ~= "table" then
    return command_error(
      "virtual filesystem directory entries must be a table",
      { reason = "resource_limit" }
    )
  end
  local names = {}
  for child_name in pairs(description.entries) do
    local valid, name_error = valid_name(child_name, fs.limits)
    if not valid then
      return nil, name_error
    end
    names[#names + 1] = child_name
  end
  table.sort(names, byte_less)
  if #names > fs.limits.max_directory_entries then
    return command_error("virtual filesystem directory entry limit is reached", {
      limit = fs.limits.max_directory_entries,
      reason = "directory_full",
    })
  end
  local okay, capacity_error = add_node(fs, "directory", 0)
  if not okay then
    return nil, capacity_error
  end
  local result = new_directory(parent, name)
  for _, child_name in ipairs(names) do
    local child, child_error =
      copy_initial_node(fs, description.entries[child_name], result, child_name, depth + 1, seen)
    if not child then
      return nil, child_error
    end
    result.children[child_name] = child
    result.child_count = result.child_count + 1
  end
  return result
end

local function components_for_node(node)
  local reversed = {}
  while node.parent do
    reversed[#reversed + 1] = node.name
    node = node.parent
  end
  local result = {}
  for index = #reversed, 1, -1 do
    result[#result + 1] = copy_string(reversed[index])
  end
  return result
end

local function node_path(components, length)
  local selected = {}
  for index = 1, length or #components do
    selected[index] = components[index]
  end
  return Path.render(selected)
end

local function resolve(fs, path)
  local resolved, resolve_error = Path.resolve(path, fs.cwd_components, fs.path_limits)
  if not resolved then
    return nil, resolve_error
  end
  return resolved
end

local function lookup_components(fs, components)
  local node = fs.root
  for index, component in ipairs(components) do
    if node.kind ~= "directory" then
      return command_error("virtual filesystem path parent is not a directory", {
        canonical_path = node_path(components, index - 1),
        reason = "not_a_directory",
      })
    end
    node = node.children[component]
    if not node then
      return command_error("virtual filesystem path does not exist", {
        canonical_path = node_path(components, index),
        reason = "not_found",
      })
    end
  end
  return node
end

local function lookup(fs, resolved)
  local node, lookup_error = lookup_components(fs, resolved.components)
  if not node then
    return nil, lookup_error
  end
  if resolved.trailing_slash and node.kind ~= "directory" then
    return command_error("virtual filesystem trailing slash requires a directory", {
      canonical_path = resolved.canonical_path,
      reason = "not_a_directory",
    })
  end
  return node
end

local function parent_and_name(fs, resolved)
  local component_count = #resolved.components
  if component_count == 0 then
    return command_error("virtual filesystem root operation is forbidden", {
      canonical_path = resolved.canonical_path,
      reason = "root_operation_forbidden",
    })
  end
  local parent_components = {}
  for index = 1, component_count - 1 do
    parent_components[index] = resolved.components[index]
  end
  local parent, parent_error = lookup_components(fs, parent_components)
  if not parent then
    return nil, parent_error
  end
  if parent.kind ~= "directory" then
    return command_error("virtual filesystem destination parent is not a directory", {
      canonical_path = node_path(parent_components),
      reason = "not_a_directory",
    })
  end
  return parent, resolved.components[component_count]
end

local function child_capacity(parent, limits)
  if parent.child_count >= limits.max_directory_entries then
    return command_error("virtual filesystem directory entry limit is reached", {
      limit = limits.max_directory_entries,
      reason = "directory_full",
    })
  end
  return true
end

local function valid_data(bytes)
  if type(bytes) ~= "string" then
    return command_error(
      "virtual filesystem file data must be a byte string",
      { reason = "resource_limit" }
    )
  end
  return bytes
end

local function check_file_size(fs, byte_count)
  if byte_count > fs.limits.max_file_bytes then
    return command_error("virtual filesystem file exceeds its byte limit", {
      limit = fs.limits.max_file_bytes,
      reason = "file_too_large",
    })
  end
  return true
end

local function check_replacement_bytes(fs, previous_bytes, next_bytes)
  local retained_without_previous = fs.retained_file_bytes - previous_bytes
  return check_increment(
    retained_without_previous,
    next_bytes,
    fs.limits.max_total_file_bytes,
    "filesystem_full",
    "virtual filesystem byte limit is reached"
  )
end

local function is_ancestor(candidate, node)
  while node do
    if node == candidate then
      return true
    end
    node = node.parent
  end
  return false
end

local function options(value, allowed, message)
  if value == nil then
    return {}
  end
  if type(value) ~= "table" then
    return command_error(message .. " options must be a table", { reason = "resource_limit" })
  end
  for name in pairs(value) do
    if not allowed[name] then
      return command_error(message .. " option is unsupported", { reason = "resource_limit" })
    end
  end
  return value
end

local function nonnegative_integer(value, name, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > maximum then
    return command_error(
      name .. " must be a non-negative bounded integer",
      { reason = "invalid_range" }
    )
  end
  return value
end

function VirtualFS.new(configuration)
  if configuration == nil then
    configuration = {}
  end
  if type(configuration) ~= "table" then
    return command_error(
      "virtual filesystem options must be a table",
      { reason = "resource_limit" }
    )
  end
  for name in pairs(configuration) do
    if name ~= "cwd" and name ~= "initial_tree" and name ~= "limits" then
      return command_error(
        "virtual filesystem option is unsupported",
        { reason = "resource_limit" }
      )
    end
  end
  local limits, limits_error = normalise_limits(configuration.limits)
  if not limits then
    return nil, limits_error
  end
  local fs = setmetatable({
    destroyed = false,
    directories = 0,
    files = 0,
    limits = limits,
    nodes = 0,
    path_limits = path_limits(limits),
    retained_file_bytes = 0,
  }, fs_mt)
  local initial_tree = configuration.initial_tree or { entries = {}, kind = "directory" }
  local root, root_error = copy_initial_node(fs, initial_tree, nil, "", 0, {})
  if not root then
    return nil, root_error
  end
  fs.root = root
  fs.cwd_node = root
  fs.cwd_components = {}
  if configuration.cwd ~= nil then
    local resolved, resolve_error = resolve(fs, configuration.cwd)
    if not resolved then
      return nil, resolve_error
    end
    local cwd_node, cwd_error = lookup(fs, resolved)
    if not cwd_node then
      return nil, cwd_error
    end
    if cwd_node.kind ~= "directory" then
      return command_error("virtual filesystem cwd must be a directory", {
        canonical_path = resolved.canonical_path,
        reason = "not_a_directory",
      })
    end
    fs.cwd_node = cwd_node
    fs.cwd_components = copy_components(resolved.components)
  end
  return fs
end

function fs_mt:stat(path)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  local node, lookup_error = lookup(self, resolved)
  if not node then
    return nil, lookup_error
  end
  local result = { canonical_path = copy_string(resolved.canonical_path), kind = node.kind }
  if node.kind == "directory" then
    result.child_count = node.child_count
  else
    result.byte_length = #node.data
  end
  return result
end

function fs_mt:list(path, configuration)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local list_options, options_error =
    options(configuration, { max_entries = true, offset = true }, "list")
  if not list_options then
    return nil, options_error
  end
  local offset, offset_error =
    nonnegative_integer(list_options.offset or 0, "list offset", self.limits.max_directory_entries)
  if not offset then
    return nil, offset_error
  end
  local maximum, maximum_error = positive_integer(
    list_options.max_entries or self.limits.max_returned_directory_entries,
    "list maximum entries",
    self.limits.max_returned_directory_entries
  )
  if not maximum then
    return nil, maximum_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  local node, lookup_error = lookup(self, resolved)
  if not node then
    return nil, lookup_error
  end
  if node.kind ~= "directory" then
    return command_error("virtual filesystem list target is not a directory", {
      canonical_path = resolved.canonical_path,
      reason = "not_a_directory",
    })
  end
  local names = sorted_keys(node.children)
  local result = {}
  local returned_bytes = 0
  local stop = math.min(#names, offset + maximum)
  for index = offset + 1, stop do
    local name = names[index]
    if #name > self.limits.max_returned_bytes - returned_bytes then
      return command_error("virtual filesystem list result exceeds its byte limit", {
        limit = self.limits.max_returned_bytes,
        reason = "resource_limit",
      })
    end
    returned_bytes = returned_bytes + #name
    result[#result + 1] = copy_string(name)
  end
  return result
end

function fs_mt:read_file(path, configuration)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local read_options, options_error =
    options(configuration, { length = true, offset = true }, "read_file")
  if not read_options then
    return nil, options_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  local node, lookup_error = lookup(self, resolved)
  if not node then
    return nil, lookup_error
  end
  if node.kind ~= "file" then
    return command_error("virtual filesystem read target is a directory", {
      canonical_path = resolved.canonical_path,
      reason = "is_a_directory",
    })
  end
  local offset, offset_error =
    nonnegative_integer(read_options.offset or 0, "read offset", #node.data)
  if not offset then
    return nil, offset_error
  end
  local length = read_options.length
  if length == nil then
    length = #node.data - offset
  end
  local valid_length, length_error = nonnegative_integer(length, "read length", #node.data - offset)
  if not valid_length then
    return nil, length_error
  end
  if valid_length > self.limits.max_returned_bytes then
    return command_error("virtual filesystem read result exceeds its byte limit", {
      limit = self.limits.max_returned_bytes,
      reason = "resource_limit",
    })
  end
  return node.data:sub(offset + 1, offset + valid_length)
end

function fs_mt:write_file(path, bytes)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local data, data_error = valid_data(bytes)
  if not data then
    return nil, data_error
  end
  local size_okay, size_error = check_file_size(self, #data)
  if not size_okay then
    return nil, size_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  if resolved.trailing_slash then
    return command_error("virtual filesystem trailing slash requires a directory", {
      canonical_path = resolved.canonical_path,
      reason = "not_a_directory",
    })
  end
  local parent, name_or_error = parent_and_name(self, resolved)
  if not parent then
    return nil, name_or_error
  end
  local name = name_or_error
  local previous = parent.children[name]
  if previous then
    if previous.kind ~= "file" then
      return command_error("virtual filesystem write target is a directory", {
        canonical_path = resolved.canonical_path,
        reason = "is_a_directory",
      })
    end
    local previous_bytes = #previous.data
    local bytes_okay, bytes_error = check_replacement_bytes(self, previous_bytes, #data)
    if not bytes_okay then
      return nil, bytes_error
    end
    previous.data = copy_string(data)
    self.retained_file_bytes = self.retained_file_bytes - previous_bytes + #data
    return true
  end
  local entry_okay, entry_error = child_capacity(parent, self.limits)
  if not entry_okay then
    return nil, entry_error
  end
  local node_okay, node_error = add_node(self, "file", #data)
  if not node_okay then
    return nil, node_error
  end
  parent.children[name] = new_file(parent, name, data)
  parent.child_count = parent.child_count + 1
  return true
end

function fs_mt:append_file(path, bytes)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local data, data_error = valid_data(bytes)
  if not data then
    return nil, data_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  local node, lookup_error = lookup(self, resolved)
  if not node then
    return nil, lookup_error
  end
  if node.kind ~= "file" then
    return command_error("virtual filesystem append target is a directory", {
      canonical_path = resolved.canonical_path,
      reason = "is_a_directory",
    })
  end
  if #data == 0 then
    return true
  end
  if #data > self.limits.max_file_bytes - #node.data then
    return command_error("virtual filesystem file exceeds its byte limit", {
      limit = self.limits.max_file_bytes,
      reason = "file_too_large",
    })
  end
  local bytes_okay, bytes_error = check_increment(
    self.retained_file_bytes,
    #data,
    self.limits.max_total_file_bytes,
    "filesystem_full",
    "virtual filesystem byte limit is reached"
  )
  if not bytes_okay then
    return nil, bytes_error
  end
  node.data = node.data .. data
  self.retained_file_bytes = self.retained_file_bytes + #data
  return true
end

function fs_mt:make_directory(path)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  local parent, name_or_error = parent_and_name(self, resolved)
  if not parent then
    return nil, name_or_error
  end
  local name = name_or_error
  local existing = parent.children[name]
  if existing then
    if resolved.trailing_slash and existing.kind ~= "directory" then
      return command_error("virtual filesystem trailing slash requires a directory", {
        canonical_path = resolved.canonical_path,
        reason = "not_a_directory",
      })
    end
    return command_error("virtual filesystem target already exists", {
      canonical_path = resolved.canonical_path,
      reason = "already_exists",
    })
  end
  local entry_okay, entry_error = child_capacity(parent, self.limits)
  if not entry_okay then
    return nil, entry_error
  end
  local node_okay, node_error = add_node(self, "directory", 0)
  if not node_okay then
    return nil, node_error
  end
  parent.children[name] = new_directory(parent, name)
  parent.child_count = parent.child_count + 1
  return true
end

function fs_mt:remove(path)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  local node, lookup_error = lookup(self, resolved)
  if not node then
    return nil, lookup_error
  end
  if node == self.root then
    return command_error("virtual filesystem root cannot be removed", {
      canonical_path = resolved.canonical_path,
      reason = "root_operation_forbidden",
    })
  end
  if is_ancestor(node, self.cwd_node) then
    return command_error("virtual filesystem cwd or ancestor cannot be removed", {
      canonical_path = resolved.canonical_path,
      reason = "cwd_operation_forbidden",
    })
  end
  if node.kind == "directory" and node.child_count ~= 0 then
    return command_error("virtual filesystem directory is not empty", {
      canonical_path = resolved.canonical_path,
      reason = "directory_not_empty",
    })
  end
  local parent = node.parent
  parent.children[node.name] = nil
  parent.child_count = parent.child_count - 1
  self.nodes = self.nodes - 1
  if node.kind == "directory" then
    self.directories = self.directories - 1
    node.children = nil
  else
    self.files = self.files - 1
    self.retained_file_bytes = self.retained_file_bytes - #node.data
    node.data = nil
  end
  node.parent = nil
  return true
end

function fs_mt:rename(source, destination)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local source_path, source_error = resolve(self, source)
  if not source_path then
    return nil, source_error
  end
  local source_node, source_lookup_error = lookup(self, source_path)
  if not source_node then
    return nil, source_lookup_error
  end
  if source_node == self.root then
    return command_error("virtual filesystem root cannot be renamed", {
      canonical_path = source_path.canonical_path,
      reason = "root_operation_forbidden",
    })
  end
  local destination_path, destination_error = resolve(self, destination)
  if not destination_path then
    return nil, destination_error
  end
  local destination_parent, name_or_error = parent_and_name(self, destination_path)
  if not destination_parent then
    return nil, name_or_error
  end
  local destination_name = name_or_error
  local destination_node = destination_parent.children[destination_name]
  if destination_node then
    if destination_path.trailing_slash and destination_node.kind ~= "directory" then
      return command_error("virtual filesystem trailing slash requires a directory", {
        canonical_path = destination_path.canonical_path,
        reason = "not_a_directory",
      })
    end
    return command_error("virtual filesystem rename destination already exists", {
      canonical_path = destination_path.canonical_path,
      reason = "already_exists",
    })
  end
  if destination_path.trailing_slash and source_node.kind ~= "directory" then
    return command_error("virtual filesystem trailing slash requires a directory", {
      canonical_path = destination_path.canonical_path,
      reason = "not_a_directory",
    })
  end
  if source_node.kind == "directory" and is_ancestor(source_node, destination_parent) then
    return command_error("virtual filesystem directory cannot move into itself", {
      canonical_path = destination_path.canonical_path,
      reason = "invalid_move",
    })
  end
  if destination_parent ~= source_node.parent then
    local entry_okay, entry_error = child_capacity(destination_parent, self.limits)
    if not entry_okay then
      return nil, entry_error
    end
  end
  local source_parent = source_node.parent
  source_parent.children[source_node.name] = nil
  source_parent.child_count = source_parent.child_count - 1
  destination_parent.children[destination_name] = source_node
  destination_parent.child_count = destination_parent.child_count + 1
  source_node.name = copy_string(destination_name)
  source_node.parent = destination_parent
  self.cwd_components = components_for_node(self.cwd_node)
  return true
end

function fs_mt:get_cwd()
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  return Path.render(self.cwd_components)
end

function fs_mt:change_directory(path)
  local live, live_error = check_live(self)
  if not live then
    return nil, live_error
  end
  local resolved, resolve_error = resolve(self, path)
  if not resolved then
    return nil, resolve_error
  end
  local node, lookup_error = lookup(self, resolved)
  if not node then
    return nil, lookup_error
  end
  if node.kind ~= "directory" then
    return command_error("virtual filesystem cwd target is not a directory", {
      canonical_path = resolved.canonical_path,
      reason = "not_a_directory",
    })
  end
  self.cwd_node = node
  self.cwd_components = copy_components(resolved.components)
  return true
end

function fs_mt:status()
  return status_copy(self)
end

function fs_mt:destroy()
  if self.destroyed then
    return true
  end
  self.cwd_components = {}
  self.cwd_node = nil
  self.directories = 0
  self.files = 0
  self.nodes = 0
  self.retained_file_bytes = 0
  self.root = nil
  self.destroyed = true
  return true
end

return VirtualFS
