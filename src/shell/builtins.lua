local Errors = require("runtime.errors")

local Builtins = {}

Builtins.contract = {
  names = "names() -> builtin_command_names",
  register = "register(registry) -> true | nil, error",
}

local definitions = {
  { name = "help", summary = "List available commands", usage = "usage: help [COMMAND]" },
  {
    capabilities = { "vfs.read" },
    name = "pwd",
    summary = "Print current directory",
    usage = "usage: pwd",
  },
  {
    capabilities = { "vfs.read" },
    name = "ls",
    summary = "List directory entries",
    usage = "usage: ls [PATH]",
  },
  {
    capabilities = { "vfs.read" },
    name = "cat",
    summary = "Write file bytes",
    usage = "usage: cat PATH",
  },
  {
    capabilities = { "vfs.write" },
    name = "write",
    summary = "Replace file bytes",
    usage = "usage: write PATH DATA",
  },
  {
    capabilities = { "vfs.write" },
    name = "mkdir",
    summary = "Create one directory",
    usage = "usage: mkdir PATH",
  },
  {
    capabilities = { "vfs.write" },
    name = "rm",
    summary = "Remove one file or empty directory",
    usage = "usage: rm PATH",
  },
  {
    capabilities = { "vfs.write" },
    name = "mv",
    summary = "Rename one path",
    usage = "usage: mv SOURCE DESTINATION",
  },
  {
    capabilities = { "vfs.chdir" },
    name = "cd",
    summary = "Change current directory",
    usage = "usage: cd PATH",
  },
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function unavailable()
  return command_error("sandbox built-in implementation is unavailable", {
    reason = "built_in_unavailable",
  })
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

local function usage(writer, text)
  local emitted, emit_error = writer:emit(text .. "\n")
  if not emitted then
    return nil, emit_error
  end
  return command_error("sandbox built-in argument count is invalid", {
    reason = "invalid_argument_count",
    usage = text,
  })
end

local function emit(writer, bytes)
  local emitted, emit_error = writer:emit(bytes)
  if not emitted then
    return nil, emit_error
  end
  return true
end

local function final_component(path)
  local start = 1
  for index = 1, #path do
    if path:byte(index) == 0x2F then
      start = index + 1
    end
  end
  return path:sub(start, #path)
end

local function child_path(parent, name)
  if parent == "/" then
    return "/" .. name
  end
  return parent .. "/" .. name
end

local function run_help(source, _, argv, writer)
  if #argv > 2 then
    return usage(writer, "usage: help [COMMAND]")
  end
  if #argv == 2 then
    local description = source.describe(argv[2])
    if not description then
      return command_error("sandbox help command is unknown", {
        name = argv[2],
        reason = "unknown_command",
      })
    end
    return emit(writer, description.usage .. "\n" .. description.summary .. "\n")
  end
  local commands = source.commands()
  table.sort(commands, function(left, right)
    return byte_less(left.name, right.name)
  end)
  local lines = {}
  for index, command in ipairs(commands) do
    lines[index] = command.name
  end
  if #lines == 0 then
    return true
  end
  return emit(writer, table.concat(lines, "\n") .. "\n")
end

local function run_pwd(context, argv, writer)
  if #argv ~= 1 then
    return usage(writer, "usage: pwd")
  end
  local path, cwd_error = context.fs:get_cwd()
  if not path then
    return nil, cwd_error
  end
  return emit(writer, path .. "\n")
end

local function run_ls(context, argv, writer)
  if #argv > 2 then
    return usage(writer, "usage: ls [PATH]")
  end
  local path = argv[2] or "."
  local target, target_error = context.fs:stat(path)
  if not target then
    return nil, target_error
  end
  if target.kind == "file" then
    return emit(writer, final_component(target.canonical_path) .. "\n")
  end
  local names, list_error = context.fs:list(path)
  if not names then
    return nil, list_error
  end
  for _, name in ipairs(names) do
    local child, child_error = context.fs:stat(child_path(target.canonical_path, name))
    if not child then
      return nil, child_error
    end
    local suffix = child.kind == "directory" and "/\n" or "\n"
    local emitted, emit_error = emit(writer, name .. suffix)
    if not emitted then
      return nil, emit_error
    end
  end
  return true
end

local function run_cat(context, argv, writer)
  if #argv ~= 2 then
    return usage(writer, "usage: cat PATH")
  end
  local data, read_error = context.fs:read_file(argv[2])
  if not data then
    return nil, read_error
  end
  return emit(writer, data)
end

local function copy_capabilities(value)
  local result = {}
  for index, capability in ipairs(value or {}) do
    result[index] = capability
  end
  return result
end

function Builtins.names()
  local result = {}
  for index, definition in ipairs(definitions) do
    result[index] = definition.name
  end
  return result
end

function Builtins.register(registry)
  if type(registry) ~= "table" or type(registry.register) ~= "function" then
    return command_error("sandbox built-ins require a command registry")
  end
  local source = {
    commands = function()
      return registry:commands()
    end,
    describe = function(name)
      return registry:describe(name)
    end,
  }
  local handlers = {
    cat = run_cat,
    help = function(context, argv, writer)
      return run_help(source, context, argv, writer)
    end,
    ls = run_ls,
    pwd = run_pwd,
  }
  for _, definition in ipairs(definitions) do
    local command_name = definition.name
    local registered, registration_error = registry:register(command_name, {
      capabilities = copy_capabilities(definition.capabilities),
      run = function(context, argv, writer)
        local handler = handlers[command_name]
        if handler then
          return handler(context, argv, writer)
        end
        return unavailable()
      end,
      summary = definition.summary,
      usage = definition.usage,
    })
    if not registered then
      return nil, registration_error
    end
  end
  return true
end

return Builtins
