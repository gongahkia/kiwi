local Errors = require("runtime.errors")

local History = {}

History.contract = {
  clear = "clear() -> true",
  get = "get(index) -> bytes | nil, error",
  length = "length() -> integer",
  list = "list(options?) -> history_entries | nil, error",
  new = "new(limits?) -> command_history | nil, error",
  normalise_limits = "normalise_limits(limits?) -> command_history_limits | nil, error",
  status = "status() -> command_history_status",
}

local default_limits = {
  max_entries = 128,
  max_entry_bytes = 4096,
  max_retained_bytes = 32768,
}

local allowed_limits = {
  max_entries = true,
  max_entry_bytes = true,
  max_retained_bytes = true,
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

function History.normalise_limits(limits)
  if limits == nil then
    limits = {}
  end
  if type(limits) ~= "table" then
    return command_error(
      "sandbox history limits must be a table",
      { reason = "invalid_history_limit" }
    )
  end
  local has_unsupported_limit = false
  for name in pairs(limits) do
    if not allowed_limits[name] then
      has_unsupported_limit = true
    end
  end
  if has_unsupported_limit then
    return command_error(
      "sandbox history limit is unsupported",
      { reason = "invalid_history_limit" }
    )
  end
  local max_entries, entries_error =
    limit(limits.max_entries, "sandbox history maximum entries", default_limits.max_entries, 0)
  if max_entries == nil then
    return nil, entries_error
  end
  local max_retained_bytes, bytes_error = limit(
    limits.max_retained_bytes,
    "sandbox history maximum retained bytes",
    default_limits.max_retained_bytes,
    0
  )
  if max_retained_bytes == nil then
    return nil, bytes_error
  end
  local disabled = max_entries == 0 or max_retained_bytes == 0
  if disabled and (max_entries ~= 0 or max_retained_bytes ~= 0) then
    return command_error("sandbox history disabling requires zero entry and byte limits", {
      max_entries = max_entries,
      max_retained_bytes = max_retained_bytes,
      reason = "invalid_history_limit",
    })
  end
  local max_entry_bytes, entry_error = limit(
    limits.max_entry_bytes,
    "sandbox history maximum entry bytes",
    default_limits.max_entry_bytes,
    disabled and 0 or 1
  )
  if max_entry_bytes == nil then
    return nil, entry_error
  end
  if not disabled and max_entry_bytes > max_retained_bytes then
    return command_error("sandbox history entry limit exceeds retained byte limit", {
      max_entry_bytes = max_entry_bytes,
      max_retained_bytes = max_retained_bytes,
      reason = "invalid_history_limit",
    })
  end
  return {
    max_entries = max_entries,
    max_entry_bytes = max_entry_bytes,
    max_retained_bytes = max_retained_bytes,
  }
end

local function copy_limits(limits)
  return {
    max_entries = limits.max_entries,
    max_entry_bytes = limits.max_entry_bytes,
    max_retained_bytes = limits.max_retained_bytes,
  }
end

function History.new(configuration)
  local limits, limits_error = History.normalise_limits(configuration)
  if not limits then
    return nil, limits_error
  end
  local entries = {}
  local entry_count = 0
  local head = 1
  local retained_bytes = 0
  local tail = 1

  local function clear()
    entries = {}
    entry_count = 0
    head = 1
    retained_bytes = 0
    tail = 1
  end

  local function evict_oldest()
    local entry = entries[head]
    entries[head] = nil
    head = head % limits.max_entries + 1
    entry_count = entry_count - 1
    retained_bytes = retained_bytes - #entry
  end

  local history = {}
  local methods = {}

  function methods:append(bytes)
    if type(bytes) ~= "string" then
      return command_error("sandbox history entry must be a byte string", {
        reason = "invalid_history_entry",
      })
    end
    if limits.max_entries == 0 then
      return command_error("sandbox history is disabled", { reason = "history_disabled" })
    end
    if #bytes > limits.max_entry_bytes or #bytes > limits.max_retained_bytes then
      return command_error("sandbox history entry exceeds its byte limit", {
        attempted_entry_bytes = #bytes,
        max_entry_bytes = limits.max_entry_bytes,
        max_retained_bytes = limits.max_retained_bytes,
        reason = "history_entry_too_large",
      })
    end
    while
      entry_count >= limits.max_entries or retained_bytes + #bytes > limits.max_retained_bytes
    do
      evict_oldest()
    end
    entries[tail] = bytes:sub(1, #bytes)
    tail = tail % limits.max_entries + 1
    entry_count = entry_count + 1
    retained_bytes = retained_bytes + #bytes
    return true
  end

  function methods:clear()
    clear()
    return true
  end

  function methods:get(index)
    if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > entry_count then
      return command_error("sandbox history index is out of range", {
        length = entry_count,
        provided = index,
        reason = "history_index_out_of_range",
      })
    end
    local position = (head + index - 2) % limits.max_entries + 1
    return entries[position]:sub(1, #entries[position])
  end

  function methods:length()
    return entry_count
  end

  function methods:limits()
    return copy_limits(limits)
  end

  function methods:list(options)
    if options == nil then
      options = {}
    end
    if type(options) ~= "table" then
      return command_error("sandbox history list options must be a table", {
        reason = "invalid_history_list",
      })
    end
    local has_unsupported_option = false
    for name in pairs(options) do
      if name ~= "max_entries" and name ~= "offset" then
        has_unsupported_option = true
      end
    end
    if has_unsupported_option then
      return command_error("sandbox history list option is unsupported", {
        reason = "invalid_history_list",
      })
    end
    local offset = options.offset or 1
    if type(offset) ~= "number" or offset % 1 ~= 0 or offset < 1 or offset > entry_count + 1 then
      return command_error("sandbox history list offset is invalid", {
        length = entry_count,
        provided = offset,
        reason = "invalid_history_list",
      })
    end
    local maximum = options.max_entries or limits.max_entries
    if
      type(maximum) ~= "number"
      or maximum % 1 ~= 0
      or maximum < 0
      or maximum > limits.max_entries
    then
      return command_error("sandbox history list maximum is invalid", {
        limit = limits.max_entries,
        provided = maximum,
        reason = "invalid_history_list",
      })
    end
    local result = {}
    for index = offset, math.min(entry_count, offset + maximum - 1) do
      local entry = assert(self:get(index))
      result[#result + 1] = entry
    end
    return result
  end

  function methods:status()
    return {
      disabled = limits.max_entries == 0,
      entries = entry_count,
      limits = copy_limits(limits),
      retained_bytes = retained_bytes,
    }
  end

  return setmetatable(history, {
    __index = methods,
    __metatable = false,
    __newindex = function(_, key)
      error("sandbox history is immutable: " .. tostring(key), 2)
    end,
  })
end

return History
