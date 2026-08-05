local Errors = require("runtime.errors")

local Tokenizer = {}

Tokenizer.contract = {
  normalise_limits = "normalise_limits(limits?) -> tokenizer_limits | nil, error",
  tokenize = "tokenize(bytes, limits?) -> argv | nil, error",
}

local default_limits = {
  max_argument_bytes = 4096,
  max_arguments = 64,
  max_input_bytes = 65536,
}

local allowed_limits = {
  max_argument_bytes = true,
  max_arguments = true,
  max_input_bytes = true,
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function limit(value, name, default, minimum)
  if value == nil then
    return default
  end
  if type(value) ~= "number" or value % 1 ~= 0 or value < minimum or value > default then
    return command_error(name .. " must be an integer within the supported bound", {
      limit = default,
      minimum = minimum,
      provided = value,
    })
  end
  return value
end

function Tokenizer.normalise_limits(limits)
  if limits == nil then
    limits = {}
  end
  if type(limits) ~= "table" then
    return command_error("tokenizer limits must be a table", { reason = "invalid_limits" })
  end
  local has_unsupported_limit = false
  for name in pairs(limits) do
    if not allowed_limits[name] then
      has_unsupported_limit = true
    end
  end
  if has_unsupported_limit then
    return command_error("tokenizer limit is unsupported", { reason = "invalid_limits" })
  end
  local max_input_bytes, input_error = limit(
    limits.max_input_bytes,
    "tokenizer maximum input bytes",
    default_limits.max_input_bytes,
    0
  )
  if not max_input_bytes then
    return nil, input_error
  end
  local max_arguments, arguments_error =
    limit(limits.max_arguments, "tokenizer maximum arguments", default_limits.max_arguments, 1)
  if not max_arguments then
    return nil, arguments_error
  end
  local max_argument_bytes, argument_error = limit(
    limits.max_argument_bytes,
    "tokenizer maximum argument bytes",
    default_limits.max_argument_bytes,
    0
  )
  if not max_argument_bytes then
    return nil, argument_error
  end
  return {
    max_argument_bytes = max_argument_bytes,
    max_arguments = max_arguments,
    max_input_bytes = max_input_bytes,
  }
end

local function tokenizer_error(reason, offset, state, detail)
  detail = detail or {}
  detail.byte_offset = offset
  detail.reason = reason
  detail.state = state
  return command_error("sandbox command tokenization failed: " .. reason, detail)
end

function Tokenizer.tokenize(bytes, limits)
  local settings, settings_error = Tokenizer.normalise_limits(limits)
  if not settings then
    return nil, settings_error
  end
  if type(bytes) ~= "string" then
    return command_error(
      "sandbox command input must be a byte string",
      { reason = "invalid_input" }
    )
  end
  if #bytes > settings.max_input_bytes then
    return tokenizer_error("input_too_large", settings.max_input_bytes, "unquoted", {
      limit = settings.max_input_bytes,
    })
  end

  local argv = {}
  local argument_chunks = {}
  local argument_length = 0
  local argument_started = false
  local index = 1
  local state = "unquoted"

  local function begin_argument(offset)
    if argument_started then
      return true
    end
    if #argv >= settings.max_arguments then
      return tokenizer_error("too_many_arguments", offset, state, {
        limit = settings.max_arguments,
      })
    end
    argument_started = true
    return true
  end

  local function append(byte, offset)
    local started, started_error = begin_argument(offset)
    if not started then
      return nil, started_error
    end
    if argument_length >= settings.max_argument_bytes then
      return tokenizer_error("argument_too_large", offset, state, {
        limit = settings.max_argument_bytes,
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
    argv[#argv + 1] = table.concat(argument_chunks)
    argument_chunks = {}
    argument_length = 0
    argument_started = false
  end

  while index <= #bytes do
    local byte = bytes:byte(index)
    local offset = index - 1
    if state == "unquoted" then
      if byte == 0x20 or byte == 0x09 then
        finish_argument()
      elseif byte == 0x27 then
        local started, started_error = begin_argument(offset)
        if not started then
          return nil, started_error
        end
        state = "single_quoted"
      elseif byte == 0x22 then
        local started, started_error = begin_argument(offset)
        if not started then
          return nil, started_error
        end
        state = "double_quoted"
      elseif byte == 0x5C then
        if index == #bytes then
          return tokenizer_error("trailing_escape", offset, state)
        end
        local appended, append_error = append(bytes:sub(index + 1, index + 1), index)
        if not appended then
          return nil, append_error
        end
        index = index + 1
      else
        local appended, append_error = append(bytes:sub(index, index), offset)
        if not appended then
          return nil, append_error
        end
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
    else
      if byte == 0x22 then
        state = "unquoted"
      elseif byte == 0x5C then
        if index == #bytes then
          return tokenizer_error("trailing_escape", offset, state)
        end
        local appended, append_error = append(bytes:sub(index + 1, index + 1), index)
        if not appended then
          return nil, append_error
        end
        index = index + 1
      else
        local appended, append_error = append(bytes:sub(index, index), offset)
        if not appended then
          return nil, append_error
        end
      end
    end
    index = index + 1
  end

  if state == "single_quoted" then
    return tokenizer_error("unterminated_single_quote", #bytes, state)
  end
  if state == "double_quoted" then
    return tokenizer_error("unterminated_double_quote", #bytes, state)
  end
  finish_argument()
  return argv
end

return Tokenizer
