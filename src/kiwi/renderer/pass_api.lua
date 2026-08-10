local Resources = require("kiwi.renderer.resources")

local Api = {}
Api.__index = Api
Api.version = 1

local function fail(message)
  error("renderer pass API: " .. message, 3)
end

local function copy_names(kind, names)
  if type(names) ~= "table" then fail(kind .. " must be a table") end
  local copy = {}
  local seen = {}
  for _, name in ipairs(names) do
    if type(name) ~= "string" or #name == 0 then fail(kind .. " must contain non-empty names") end
    if seen[name] then fail(kind .. " must not repeat " .. name) end
    seen[name] = true
    copy[#copy + 1] = name
  end
  return copy
end

local function identity(kind, value)
  if type(value) ~= "string" or value:match("^[a-z][a-z0-9_-]*$") == nil then
    fail(kind .. " must match [a-z][a-z0-9_-]*")
  end
  return value
end

local function copy_viewport(viewport)
  local copy = {}
  for key, value in pairs(viewport) do
    if type(key) == "string" and (type(value) == "number" or type(value) == "string" or type(value) == "boolean") then
      copy[key] = value
    else
      fail("resize descriptors must contain plain scalar fields")
    end
  end
  return copy
end

local function public_pass(pass)
  return { id = pass.name, extension = pass.extension, name = pass.extension_name, order = pass.order }
end

local function callback_context(renderer, pass, phase, resize)
  local context = {
    api_version = Api.version,
    pass = public_pass(pass),
    phase = phase,
    resources = renderer:resolve_pass_resources(pass),
    request_animation = function(delay)
      return renderer:schedule_animation("extension", renderer.frame_time, delay)
    end,
  }
  if resize then
    context.resize = {
      previous = copy_viewport(resize.previous),
      current = copy_viewport(resize.current),
    }
  end
  return context
end

local function require_callback(declaration, name, required)
  local callback = declaration[name]
  if callback == nil and not required then return nil end
  if type(callback) ~= "function" then fail(name .. " callback must be a function") end
  return callback
end

function Api.new()
  return setmetatable({ passes = {} }, Api)
end

function Api:register(declaration)
  if type(declaration) ~= "table" then fail("pass declaration must be a table") end
  if declaration.api_version ~= Api.version then
    fail("pass API version " .. tostring(declaration.api_version) .. " is incompatible; supported version is " .. Api.version)
  end
  local extension = identity("extension", declaration.extension)
  local name = identity("pass name", declaration.name)
  if type(declaration.order) ~= "number" or declaration.order % 1 ~= 0 then
    fail("pass " .. extension .. "/" .. name .. " needs an integer order")
  end
  local reads = copy_names("read resources", declaration.reads)
  local writes = copy_names("write resources", declaration.writes)
  local after = copy_names("ordering constraints", declaration.after)
  for _, resource in ipairs(reads) do
    if not Resources.allows(resource, "read") then fail("pass " .. extension .. "/" .. name .. " cannot read resource " .. resource) end
  end
  for _, resource in ipairs(writes) do
    if not Resources.allows(resource, "write") then fail("pass " .. extension .. "/" .. name .. " cannot write resource " .. resource) end
  end
  local callbacks = {
    initialize = require_callback(declaration, "initialize", false),
    encode = require_callback(declaration, "encode", true),
    resize = require_callback(declaration, "resize", false),
    shutdown = require_callback(declaration, "shutdown", false),
  }
  local pass = {
    name = "extension/" .. extension .. "/" .. name,
    extension = extension,
    extension_name = name,
    order = declaration.order,
    reads = reads,
    writes = writes,
    after = after,
  }
  function pass:initialize(renderer)
    if callbacks.initialize then callbacks.initialize(callback_context(renderer, self, "initialize")) end
  end
  function pass:encode(renderer)
    callbacks.encode(callback_context(renderer, self, "encode"))
  end
  function pass:resize(renderer, previous, current)
    if callbacks.resize then
      callbacks.resize(callback_context(renderer, self, "resize", { previous = previous, current = current }))
    end
  end
  function pass:shutdown(renderer)
    if callbacks.shutdown then callbacks.shutdown(callback_context(renderer, self, "shutdown")) end
  end
  self.passes[#self.passes + 1] = pass
  return public_pass(pass)
end

function Api:register_extensions(registrations)
  if registrations == nil then return end
  if type(registrations) ~= "table" then fail("extension registrations must be a table") end
  for index, register in ipairs(registrations) do
    if type(register) ~= "function" then fail("extension registration " .. index .. " must be a function") end
    register(self)
  end
end

return Api
