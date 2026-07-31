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

local function copy_arguments(arguments)
  local values = {}
  for index, argument in ipairs(arguments) do
    values[index] = argument:sub(1, #argument)
  end
  return setmetatable({}, {
    __index = values,
    __metatable = false,
    __newindex = function(_, key)
      error("sandbox completion arguments are immutable: " .. tostring(key), 2)
    end,
  })
end

local function immutable_request(values)
  return setmetatable({}, {
    __index = values,
    __metatable = false,
    __newindex = function(_, key)
      error("sandbox completion request is immutable: " .. tostring(key), 2)
    end,
  })
end

local function has_completion_capability(command)
  for _, capability in ipairs(command.capabilities) do
    if capability == "completion" then
      return true
    end
  end
  return false
end

local function dense_array(value)
  if type(value) ~= "table" then
    return nil
  end
  local length = #value
  for key in pairs(value) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
      return nil
    end
  end
  return length
end

local function callback_candidate(value, request, replacement_end, limits)
  local candidate = value
  if type(value) == "string" then
    candidate = { value = value }
  end
  if type(candidate) ~= "table" then
    return command_error("sandbox completion callback returned an invalid candidate", {
      reason = "invalid_callback_return",
    })
  end
  local allowed_fields = {
    category = true,
    description = true,
    display = true,
    replace_end = true,
    replace_start = true,
    sort_key = true,
    value = true,
  }
  local has_unknown_field = false
  for name in pairs(candidate) do
    if not allowed_fields[name] then
      has_unknown_field = true
    end
  end
  if has_unknown_field or type(candidate.value) ~= "string" then
    return command_error("sandbox completion callback returned an invalid candidate", {
      reason = "invalid_callback_return",
    })
  end
  local replace_start = candidate.replace_start
  local replace_end = candidate.replace_end
  if replace_start == nil and replace_end == nil then
    replace_start = request.replace_start
    replace_end = replacement_end
  elseif replace_start == nil or replace_end == nil then
    return command_error("sandbox completion replacement range is invalid", {
      reason = "invalid_replacement_range",
    })
  end
  if
    type(replace_start) ~= "number"
    or replace_start % 1 ~= 0
    or type(replace_end) ~= "number"
    or replace_end % 1 ~= 0
    or replace_start < 0
    or replace_start > replace_end
    or replace_end > #request.line
  then
    return command_error("sandbox completion replacement range is invalid", {
      reason = "invalid_replacement_range",
    })
  end
  local display = candidate.display or candidate.value
  local description = candidate.description
  local category = candidate.category
  local sort_key = candidate.sort_key or display
  if
    type(display) ~= "string"
    or (description ~= nil and type(description) ~= "string")
    or (category ~= nil and type(category) ~= "string")
    or type(sort_key) ~= "string"
  then
    return command_error("sandbox completion callback returned an invalid candidate", {
      reason = "invalid_callback_return",
    })
  end
  local insertion = encode_argument(candidate.value)
  if
    #insertion > limits.max_candidate_insertion_bytes
    or #display > limits.max_display_bytes
    or (description and #description > limits.max_display_bytes)
    or (category and #category > limits.max_display_bytes)
    or #sort_key > limits.max_display_bytes
  then
    return command_error("sandbox completion candidate is too large", {
      reason = "candidate_too_large",
    })
  end
  return {
    category = category and category:sub(1, #category) or nil,
    description = description and description:sub(1, #description) or nil,
    display = display:sub(1, #display),
    insertion = insertion,
    replace_end = replace_end,
    replace_start = replace_start,
    sort_key = sort_key:sub(1, #sort_key),
  }
end

local function duplicate(candidates, candidate)
  for _, existing in ipairs(candidates) do
    if
      existing.category == candidate.category
      and existing.description == candidate.description
      and existing.display == candidate.display
      and existing.insertion == candidate.insertion
      and existing.replace_end == candidate.replace_end
      and existing.replace_start == candidate.replace_start
      and existing.sort_key == candidate.sort_key
    then
      return true
    end
  end
  return false
end

local function candidate_bytes(candidate)
  return #candidate.display
    + #candidate.insertion
    + #candidate.sort_key
    + (candidate.category and #candidate.category or 0)
    + (candidate.description and #candidate.description or 0)
end

local function callback_request(command, bytes, cursor_offset, scan, replacement_end)
  return immutable_request({
    active_argument_index = scan.argument_index,
    active_prefix = scan.active_prefix:sub(1, #scan.active_prefix),
    command = command.name,
    completed_argument_count = #scan.completed_arguments,
    completed_arguments = copy_arguments(scan.completed_arguments),
    cursor_offset = cursor_offset,
    line = bytes:sub(1, #bytes),
    pending_escape = scan.pending_escape,
    quote_mode = scan.quote_mode,
    replace_end = replacement_end,
    replace_start = scan.active_start,
  })
end

function Completion.new(registry, configuration)
  if type(registry) ~= "table" or type(registry.commands) ~= "function" then
    return command_error("sandbox completion requires a command registry")
  end
  local limits, limits_error = options(configuration)
  if not limits then
    return nil, limits_error
  end
  return setmetatable({ completing = false, limits = limits, registry = registry }, completion_mt)
end

function completion_mt:complete(bytes, cursor_offset)
  if self.completing then
    self.reentrant = true
    return command_error(
      "sandbox completion is reentrant",
      { reason = "reentrant_completion_call" }
    )
  end
  local scan, scan_error = Scanner.scan(bytes, cursor_offset, self.limits.scanner_limits)
  if not scan then
    return nil, scan_error
  end
  local commands, commands_error = sorted_commands(self.registry)
  if not commands then
    return nil, commands_error
  end
  local result = { candidates = {}, scan = scan }
  local replacement_end = argument_end(bytes, cursor_offset, scan)
  if scan.argument_index == 1 then
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

  local command_name = scan.completed_arguments[1]
  local command_descriptor = nil
  for _, descriptor in ipairs(commands) do
    if descriptor.name == command_name then
      command_descriptor = descriptor
      break
    end
  end
  if not command_descriptor then
    return result
  end
  local command, command_error_value = self.registry:command(command_name)
  if not command then
    return nil, command_error_value
  end
  if command.complete == nil then
    if has_completion_capability(command) then
      return command_error("sandbox completion capability has no callback", {
        capability = "completion",
        reason = "unknown_completion_capability",
      })
    end
    return result
  end
  local request = callback_request(command, bytes, cursor_offset, scan, replacement_end)
  self.completing = true
  self.reentrant = false
  local ok, callback_result = pcall(command.complete, request)
  local reentrant = self.reentrant
  self.completing = false
  self.reentrant = false
  if reentrant then
    return command_error("sandbox completion callback reentered completion", {
      reason = "reentrant_completion_call",
    })
  end
  if not ok then
    return command_error("sandbox completion callback failed", { reason = "callback_failure" })
  end
  local length = dense_array(callback_result)
  if not length then
    return command_error("sandbox completion callback returned an invalid candidate list", {
      reason = "invalid_callback_return",
    })
  end
  if length > self.limits.max_candidates then
    return command_error("sandbox completion has too many candidates", {
      limit = self.limits.max_candidates,
      reason = "too_many_candidates",
    })
  end
  local total_bytes = 0
  for _, value in ipairs(callback_result) do
    local candidate, candidate_error =
      callback_candidate(value, request, replacement_end, self.limits)
    if not candidate then
      return nil, candidate_error
    end
    if not duplicate(result.candidates, candidate) then
      total_bytes = total_bytes + candidate_bytes(candidate)
      if total_bytes > self.limits.max_total_candidate_bytes then
        return command_error("sandbox completion candidates exceed their byte limit", {
          limit = self.limits.max_total_candidate_bytes,
          reason = "candidate_too_large",
        })
      end
      result.candidates[#result.candidates + 1] = candidate
    end
  end
  return result
end

return Completion
