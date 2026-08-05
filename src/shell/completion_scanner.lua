local Errors = require("runtime.errors")

local Scanner = {}

Scanner.contract = {
  normalise_limits = "normalise_limits(limits?) -> completion_scan_limits | nil, error",
  scan = "scan(bytes, cursor_offset, limits?) -> completion_scan | nil, error",
}

local default_limits = {
  max_active_prefix_bytes = 4096,
  max_arguments = 64,
  max_input_bytes = 65536,
  max_scanned_argument_bytes = 4096,
}

local allowed_limits = {
  max_active_prefix_bytes = true,
  max_arguments = true,
  max_input_bytes = true,
  max_scanned_argument_bytes = true,
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

function Scanner.normalise_limits(limits)
  if limits == nil then
    limits = {}
  end
  if type(limits) ~= "table" then
    return command_error("sandbox completion scan limits must be a table", {
      reason = "scan_resource_limit",
    })
  end
  local has_unsupported_limit = false
  for name in pairs(limits) do
    if not allowed_limits[name] then
      has_unsupported_limit = true
    end
  end
  if has_unsupported_limit then
    return command_error("sandbox completion scan limit is unsupported", {
      reason = "scan_resource_limit",
    })
  end
  local max_input_bytes, input_error = limit(
    limits.max_input_bytes,
    "sandbox completion maximum input bytes",
    default_limits.max_input_bytes
  )
  if not max_input_bytes then
    return nil, input_error
  end
  local max_arguments, arguments_error = limit(
    limits.max_arguments,
    "sandbox completion maximum arguments",
    default_limits.max_arguments
  )
  if not max_arguments then
    return nil, arguments_error
  end
  local max_scanned_argument_bytes, argument_error = limit(
    limits.max_scanned_argument_bytes,
    "sandbox completion maximum scanned argument bytes",
    default_limits.max_scanned_argument_bytes
  )
  if not max_scanned_argument_bytes then
    return nil, argument_error
  end
  local max_active_prefix_bytes, prefix_error = limit(
    limits.max_active_prefix_bytes,
    "sandbox completion maximum active prefix bytes",
    default_limits.max_active_prefix_bytes
  )
  if not max_active_prefix_bytes then
    return nil, prefix_error
  end
  return {
    max_active_prefix_bytes = max_active_prefix_bytes,
    max_arguments = max_arguments,
    max_input_bytes = max_input_bytes,
    max_scanned_argument_bytes = max_scanned_argument_bytes,
  }
end

local function scan_error(reason, offset, state, detail)
  detail = detail or {}
  detail.byte_offset = offset
  detail.reason = reason
  detail.state = state
  return command_error("sandbox completion scan failed: " .. reason, detail)
end

function Scanner.scan(bytes, cursor_offset, limits)
  local settings, settings_error = Scanner.normalise_limits(limits)
  if not settings then
    return nil, settings_error
  end
  if type(bytes) ~= "string" then
    return command_error("sandbox completion input must be a byte string", {
      reason = "invalid_completion_input",
    })
  end
  if #bytes > settings.max_input_bytes then
    return scan_error("input_too_large", settings.max_input_bytes, "unquoted", {
      limit = settings.max_input_bytes,
    })
  end
  if
    type(cursor_offset) ~= "number"
    or cursor_offset % 1 ~= 0
    or cursor_offset < 0
    or cursor_offset > #bytes
  then
    return command_error("sandbox completion cursor offset is invalid", {
      length = #bytes,
      provided = cursor_offset,
      reason = "invalid_cursor_offset",
    })
  end

  local completed_arguments = {}
  local argument_chunks = {}
  local argument_length = 0
  local argument_started = false
  local argument_start = cursor_offset
  local index = 1
  local pending_escape = false
  local state = "unquoted"

  local function begin_argument(offset)
    if argument_started then
      return true
    end
    if #completed_arguments >= settings.max_arguments then
      return scan_error("scan_resource_limit", offset, state, {
        limit = settings.max_arguments,
      })
    end
    argument_chunks = {}
    argument_length = 0
    argument_started = true
    argument_start = offset
    return true
  end

  local function append(byte, offset)
    local started, started_error = begin_argument(offset)
    if not started then
      return nil, started_error
    end
    if argument_length >= settings.max_scanned_argument_bytes then
      return scan_error("scan_resource_limit", offset, state, {
        limit = settings.max_scanned_argument_bytes,
      })
    end
    argument_length = argument_length + 1
    argument_chunks[#argument_chunks + 1] = byte
    return true
  end

  local function finish_argument()
    if not argument_started then
      return
    end
    completed_arguments[#completed_arguments + 1] = table.concat(argument_chunks)
    argument_chunks = {}
    argument_length = 0
    argument_started = false
  end

  while index <= cursor_offset do
    local byte = bytes:byte(index)
    local offset = index - 1
    if state == "unquoted" then
      if byte == 0x20 or byte == 0x09 then
        finish_argument()
        argument_start = offset + 1
        pending_escape = false
      elseif byte == 0x27 then
        local started, started_error = begin_argument(offset)
        if not started then
          return nil, started_error
        end
        state = "single_quoted"
        pending_escape = false
      elseif byte == 0x22 then
        local started, started_error = begin_argument(offset)
        if not started then
          return nil, started_error
        end
        state = "double_quoted"
        pending_escape = false
      elseif byte == 0x5C then
        local started, started_error = begin_argument(offset)
        if not started then
          return nil, started_error
        end
        if index == cursor_offset then
          pending_escape = true
        else
          local appended, append_error = append(bytes:sub(index + 1, index + 1), index)
          if not appended then
            return nil, append_error
          end
          index = index + 1
          pending_escape = false
        end
      else
        local appended, append_error = append(bytes:sub(index, index), offset)
        if not appended then
          return nil, append_error
        end
        pending_escape = false
      end
    elseif state == "single_quoted" then
      if byte == 0x27 then
        state = "unquoted"
      else
        local appended, append_error = append(bytes:sub(index, index), offset)
        if not appended then
          return nil, append_error
        end
      end
      pending_escape = false
    else
      if byte == 0x22 then
        state = "unquoted"
        pending_escape = false
      elseif byte == 0x5C then
        if index == cursor_offset then
          pending_escape = true
        else
          local appended, append_error = append(bytes:sub(index + 1, index + 1), index)
          if not appended then
            return nil, append_error
          end
          index = index + 1
          pending_escape = false
        end
      else
        local appended, append_error = append(bytes:sub(index, index), offset)
        if not appended then
          return nil, append_error
        end
        pending_escape = false
      end
    end
    index = index + 1
  end

  if argument_length > settings.max_active_prefix_bytes then
    return scan_error("scan_resource_limit", cursor_offset, state, {
      limit = settings.max_active_prefix_bytes,
    })
  end
  local active_prefix = table.concat(argument_chunks)
  local copied_arguments = {}
  for argument_index, argument in ipairs(completed_arguments) do
    copied_arguments[argument_index] = argument:sub(1, #argument)
  end
  return {
    active_prefix = active_prefix,
    active_start = argument_started and argument_start or cursor_offset,
    argument_index = #completed_arguments + 1,
    completed_arguments = copied_arguments,
    cursor_offset = cursor_offset,
    between_arguments = not argument_started,
    pending_escape = pending_escape,
    quote_mode = state,
  }
end

return Scanner
