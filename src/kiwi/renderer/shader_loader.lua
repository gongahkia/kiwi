local ffi = require("ffi")

local Loader = {}
Loader.__index = Loader
Loader.max_source_bytes = 1024 * 1024

local function fail(definition, stage, detail)
  error(string.format(
    "shader module %s for pass %s from %s %s: %s",
    definition.id,
    definition.pass,
    definition.path,
    stage,
    detail
  ), 3)
end

local function validate_definition(definition)
  assert(type(definition) == "table", "shader module definition must be a table")
  for _, field in ipairs({ "id", "pass", "path" }) do
    assert(type(definition[field]) == "string" and #definition[field] > 0, "shader module " .. field .. " must be a non-empty string")
  end
end

local function read_source(path)
  local file, error_message = io.open(path, "rb")
  if not file then
    return nil, error_message
  end
  local source = file:read("*a")
  file:close()
  return source
end

local function source_fingerprint(source)
  local hash = 5381
  for index = 1, #source do
    hash = (hash * 33 + source:byte(index)) % 4294967296
  end
  return string.format("%08x:%d", hash, #source)
end

local function has_error(diagnostics)
  return diagnostics:match("^error ") ~= nil or diagnostics:match("\nerror ") ~= nil
end

function Loader.new(options)
  options = options or {}
  return setmetatable({
    read_source = options.read_source or read_source,
    compile = assert(options.compile, "shader loader needs a compile function"),
    max_source_bytes = options.max_source_bytes or Loader.max_source_bytes,
  }, Loader)
end

function Loader:read(definition)
  validate_definition(definition)
  local source, read_error = self.read_source(definition.path)
  if source == nil then
    fail(definition, "could not read source", tostring(read_error))
  end
  if type(source) ~= "string" then
    fail(definition, "could not read source", "source reader returned " .. type(source))
  end
  if #source > self.max_source_bytes then
    fail(definition, "could not read source", "source exceeds " .. self.max_source_bytes .. " byte limit")
  end
  return source
end

function Loader:fingerprint(source)
  assert(type(source) == "string", "shader source must be a string")
  return source_fingerprint(source)
end

function Loader:load_source(definition, source)
  validate_definition(definition)
  if type(source) ~= "string" then
    fail(definition, "compilation failed", "source must be a string")
  end
  local result, compile_error = self.compile(definition, source)
  if result == nil then
    fail(definition, "compilation failed", tostring(compile_error))
  end
  local diagnostics = result.diagnostics or ""
  if has_error(diagnostics) then
    if result.release then result:release() end
    fail(definition, "compilation failed", diagnostics)
  end
  return {
    id = definition.id,
    pass = definition.pass,
    path = definition.path,
    source_bytes = #source,
    source_fingerprint = self:fingerprint(source),
    handle = result.handle,
    diagnostics = diagnostics,
    release = result.release,
  }
end

function Loader:load(definition)
  return self:load_source(definition, self:read(definition))
end

function Loader.native(context, registry)
  return Loader.new({
    compile = function(definition, source)
      local module = context.native.surface.kiwi_shader_from_wgsl(context.device, source)
      if module == nil then
        local native_error = ffi.string(context.native.surface.kiwi_surface_last_error())
        context.native.surface.kiwi_surface_clear_error()
        return nil, native_error
      end
      local released = false
      local function release()
        if released then return end
        released = true
        registry:release_native(module)
      end
      registry:own_native("shader:" .. definition.id, module, context.native.lib.wgpuShaderModuleRelease)
      context.native.lib.wgpuInstanceProcessEvents(context.instance)
      local native_error = ffi.string(context.native.surface.kiwi_surface_last_error())
      if #native_error > 0 then
        context.native.surface.kiwi_surface_clear_error()
        release()
        return nil, native_error
      end
      return { handle = module, diagnostics = "", release = release }
    end,
  })
end

return Loader
