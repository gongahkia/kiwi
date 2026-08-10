local Registry = {}
Registry.__index = Registry

local resource_specs = {
  ["terminal.cells"] = { access = "read" },
  ["text.shaped_glyphs"] = { access = "read" },
  ["terminal.cursor"] = { access = "read" },
  ["terminal.selection"] = { access = "read" },
  ["terminal.search"] = { access = "read" },
  ["terminal.hyperlinks"] = { access = "read" },
  ["terminal.command_regions"] = { access = "read" },
  ["terminal.kitty_images"] = { access = "read" },
  ["terminal.damage"] = { access = "read" },
  ["frame.viewport"] = { access = "read" },
  ["frame.timing"] = { access = "read" },
  ["text.alpha_atlas"] = { access = "read" },
  ["surface.color"] = { access = "write" },
}

local function fail(message)
  error("render resource registry: " .. message, 3)
end

local function copy_descriptor(value, seen)
  local value_type = type(value)
  if value_type == "string" or value_type == "number" or value_type == "boolean" or value == nil then
    return value
  end
  if value_type ~= "table" then
    fail("descriptor values must be plain data, not " .. value_type)
  end
  if getmetatable(value) ~= nil then
    fail("descriptor values must not have metatables")
  end
  seen = seen or {}
  if seen[value] then
    fail("descriptor values must not be cyclic")
  end
  seen[value] = true
  local copy = {}
  for key, item in pairs(value) do
    if type(key) ~= "string" then
      fail("descriptor keys must be strings")
    end
    copy[key] = copy_descriptor(item, seen)
  end
  seen[value] = nil
  return copy
end

local function validate_descriptor(name, descriptor)
  if type(descriptor) ~= "table" then
    fail("descriptor for " .. name .. " must be a table")
  end
  local spec = resource_specs[name]
  if spec == nil then
    fail("unknown resource " .. tostring(name))
  end
  if descriptor.kind ~= name then
    fail("resource " .. name .. " must declare kind " .. name)
  end
  if descriptor.access ~= spec.access then
    fail("resource " .. name .. " must declare " .. spec.access .. " access")
  end
  return copy_descriptor(descriptor)
end

function Registry.allows(name, access)
  local spec = resource_specs[name]
  return spec ~= nil and spec.access == access
end

function Registry.new(generation)
  assert(type(generation) == "number" and generation >= 1 and generation % 1 == 0, "render resource generation must be a positive integer")
  return setmetatable({
    generation = generation,
    identity = {},
    entries = {},
    owned = {},
    owned_handles = {},
    destroyed = false,
  }, Registry)
end

function Registry:assert_active()
  if self.destroyed then
    fail("registry generation " .. self.generation .. " is destroyed")
  end
end

function Registry:entry_for(handle)
  self:assert_active()
  if type(handle) ~= "table" or handle.registry ~= self.identity then
    fail("resource handle belongs to a different registry")
  end
  if handle.generation ~= self.generation then
    fail("resource handle " .. tostring(handle.name) .. " is stale")
  end
  local entry = self.entries[handle.name]
  if entry == nil or entry.handle ~= handle then
    fail("unknown resource handle " .. tostring(handle.name))
  end
  return entry
end

function Registry:register(name, descriptor)
  self:assert_active()
  if self.entries[name] ~= nil then
    fail("resource " .. tostring(name) .. " is already registered")
  end
  local handle = { registry = self.identity, generation = self.generation, name = name }
  self.entries[name] = {
    handle = handle,
    descriptor = validate_descriptor(name, descriptor),
  }
  return handle
end

function Registry:update(handle, descriptor)
  local entry = self:entry_for(handle)
  entry.descriptor = validate_descriptor(handle.name, descriptor)
end

function Registry:resolve(handle, access)
  local entry = self:entry_for(handle)
  if access ~= nil and entry.descriptor.access ~= access then
    fail("resource " .. handle.name .. " does not permit " .. access .. " access")
  end
  return {
    name = handle.name,
    generation = self.generation,
    descriptor = copy_descriptor(entry.descriptor),
  }
end

function Registry:own_native(label, handle, release, destroy)
  self:assert_active()
  if handle == nil then
    fail("native resource " .. label .. " has a null handle")
  end
  if type(label) ~= "string" or #label == 0 then
    fail("native resource label must be a non-empty string")
  end
  local release_type = type(release)
  if release_type ~= "function" and release_type ~= "cdata" then
    fail("native resource " .. label .. " needs a release function")
  end
  if self.owned_handles[handle] then
    fail("native resource " .. label .. " is already owned")
  end
  local item = { label = label, handle = handle, release = release, destroy = destroy }
  self.owned_handles[handle] = item
  self.owned[#self.owned + 1] = item
  return handle
end

local function release_native_item(item)
  if item.released then
    return
  end
  item.released = true
  local first_error
  if item.destroy then
    local ok, message = pcall(item.destroy, item.handle)
    if not ok then first_error = item.label .. " destroy failed: " .. message end
  end
  local ok, message = pcall(item.release, item.handle)
  if not ok and first_error == nil then first_error = item.label .. " release failed: " .. message end
  return first_error
end

function Registry:release_native(handle)
  self:assert_active()
  local item = self.owned_handles[handle]
  if item == nil then
    fail("native resource is not owned by this registry")
  end
  self.owned_handles[handle] = nil
  local message = release_native_item(item)
  if message then fail(message) end
end

function Registry:destroy()
  if self.destroyed then
    return
  end
  self.destroyed = true
  local first_error
  for index = #self.owned, 1, -1 do
    local item = self.owned[index]
    local message = release_native_item(item)
    if message and first_error == nil then
      first_error = message
    end
  end
  self.entries = {}
  self.owned = {}
  self.owned_handles = {}
  if first_error then error("render resource registry: " .. first_error, 2) end
end

return Registry
