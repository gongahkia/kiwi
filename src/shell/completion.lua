local Errors = require("runtime.errors")
local Scanner = require("shell.completion_scanner")

local Completion = {}
local completion_mt = {}
completion_mt.__index = completion_mt

Completion.contract = {
  complete = "complete(bytes, cursor_offset) -> completion_result | nil, error",
  new = "new(registry, limits?) -> completion_engine | nil, error",
}

local default_limits = {
  max_candidate_insertion_bytes = 4096,
  max_candidates = 64,
  max_display_bytes = 256,
  max_total_candidate_bytes = 16384,
}

local allowed_limits = {
  max_candidate_insertion_bytes = true,
  max_candidates = true,
  max_display_bytes = true,
  max_total_candidate_bytes = true,
  scanner_limits = true,
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function limit(value, name, default)
  if value == nil then
    return default
  end
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > default then
    return command_error(name .. " must be an integer within the supported bound", {
      limit = default,
      minimum = 1,
      provided = value,
    })
  end
  return value
end

local function options(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return command_error("sandbox completion limits must be a table")
  end
  local has_unsupported_limit = false
  for name in pairs(value) do
    if not allowed_limits[name] then
      has_unsupported_limit = true
    end
  end
  if has_unsupported_limit then
    return command_error("sandbox completion limit is unsupported")
  end
  local scanner_limits, scanner_error = Scanner.normalise_limits(value.scanner_limits)
  if not scanner_limits then
    return nil, scanner_error
  end
  local max_candidates, candidates_error = limit(
    value.max_candidates,
    "sandbox completion maximum candidates",
    default_limits.max_candidates
  )
  if not max_candidates then
    return nil, candidates_error
  end
  local max_candidate_insertion_bytes, insertion_error = limit(
    value.max_candidate_insertion_bytes,
    "sandbox completion maximum insertion bytes",
    default_limits.max_candidate_insertion_bytes
  )
  if not max_candidate_insertion_bytes then
    return nil, insertion_error
  end
  local max_total_candidate_bytes, total_error = limit(
    value.max_total_candidate_bytes,
    "sandbox completion maximum candidate bytes",
    default_limits.max_total_candidate_bytes
  )
  if not max_total_candidate_bytes then
    return nil, total_error
  end
  local max_display_bytes, display_error = limit(
    value.max_display_bytes,
    "sandbox completion maximum display bytes",
    default_limits.max_display_bytes
  )
  if not max_display_bytes then
    return nil, display_error
  end
  return {
    max_candidate_insertion_bytes = max_candidate_insertion_bytes,
    max_candidates = max_candidates,
    max_display_bytes = max_display_bytes,
    max_total_candidate_bytes = max_total_candidate_bytes,
    scanner_limits = scanner_limits,
  }
end

local function encode_argument(bytes)
  return '"' .. bytes:gsub('[\\"]', "\\%0") .. '"'
end

local function argument_end(bytes, cursor_offset, scan)
  local index = cursor_offset + 1
  local pending_escape = scan.pending_escape
  local state = scan.quote_mode
  while index <= #bytes do
    local byte = bytes:byte(index)
    if pending_escape then
      pending_escape = false
    elseif state == "unquoted" then
      if byte == 0x20 or byte == 0x09 then
        return index - 1
      elseif byte == 0x27 then
        state = "single_quoted"
      elseif byte == 0x22 then
        state = "double_quoted"
      elseif byte == 0x5C then
        pending_escape = true
      end
    elseif state == "single_quoted" then
      if byte == 0x27 then
        state = "unquoted"
      end
    elseif byte == 0x22 then
      state = "unquoted"
    elseif byte == 0x5C then
      pending_escape = true
    end
    index = index + 1
  end
  return #bytes
end

local function sorted_commands(registry)
  local commands, commands_error = registry:commands()
  if not commands then
    return nil, commands_error
  end
  table.sort(commands, function(left, right)
    return left.name < right.name
  end)
  return commands
end

function Completion.new(registry, configuration)
  if type(registry) ~= "table" or type(registry.commands) ~= "function" then
    return command_error("sandbox completion requires a command registry")
  end
  local limits, limits_error = options(configuration)
  if not limits then
    return nil, limits_error
  end
  return setmetatable({ limits = limits, registry = registry }, completion_mt)
end

function completion_mt:complete(bytes, cursor_offset)
  local scan, scan_error = Scanner.scan(bytes, cursor_offset, self.limits.scanner_limits)
  if not scan then
    return nil, scan_error
  end
  local result = { candidates = {}, scan = scan }
  if scan.argument_index ~= 1 then
    return result
  end
  local commands, commands_error = sorted_commands(self.registry)
  if not commands then
    return nil, commands_error
  end
  local replacement_end = argument_end(bytes, cursor_offset, scan)
  local total_bytes = 0
  for _, command in ipairs(commands) do
    if command.name:sub(1, #scan.active_prefix) == scan.active_prefix then
      if #result.candidates >= self.limits.max_candidates then
        return command_error("sandbox completion has too many candidates", {
          limit = self.limits.max_candidates,
          reason = "too_many_candidates",
        })
      end
      local insertion = encode_argument(command.name)
      if #insertion > self.limits.max_candidate_insertion_bytes then
        return command_error("sandbox completion insertion is too large", {
          limit = self.limits.max_candidate_insertion_bytes,
          reason = "candidate_too_large",
        })
      end
      if #command.name > self.limits.max_display_bytes then
        return command_error("sandbox completion display is too large", {
          limit = self.limits.max_display_bytes,
          reason = "candidate_too_large",
        })
      end
      total_bytes = total_bytes + #insertion + #command.name
      if total_bytes > self.limits.max_total_candidate_bytes then
        return command_error("sandbox completion candidates exceed their byte limit", {
          limit = self.limits.max_total_candidate_bytes,
          reason = "candidate_too_large",
        })
      end
      result.candidates[#result.candidates + 1] = {
        display = command.name:sub(1, #command.name),
        insertion = insertion,
        replace_end = replacement_end,
        replace_start = scan.active_start,
        sort_key = command.name:sub(1, #command.name),
      }
    end
  end
  return result
end

return Completion
