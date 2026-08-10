local ffi = require("ffi")

local Loader = {}
Loader.__index = Loader

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

local function has_error(diagnostics)
  return diagnostics:match("^error ") ~= nil or diagnostics:match("\nerror ") ~= nil
end

function Loader.new(options)
  options = options or {}
  return setmetatable({
    read_source = options.read_source or read_source,
    compile = assert(options.compile, "shader loader needs a compile function"),
  }, Loader)
end

function Loader:load(definition)
  validate_definition(definition)
  local source, read_error = self.read_source(definition.path)
  if source == nil then
    fail(definition, "could not read source", tostring(read_error))
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
    handle = result.handle,
    diagnostics = diagnostics,
    release = result.release,
  }
end

function Loader.native(context, registry)
  return Loader.new({
    compile = function(definition, source)
      local module = context.native.surface.kiwi_shader_from_wgsl(context.device, source)
      if module == nil then
        return nil, ffi.string(context.native.surface.kiwi_surface_last_error())
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
        release()
        return nil, native_error
      end
      return { handle = module, diagnostics = "", release = release }
    end,
  })
end

return Loader
