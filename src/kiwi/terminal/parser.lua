local Actions = require("kiwi.terminal.actions")
local Utf8 = require("kiwi.terminal.utf8")

local Parser = {}
Parser.__index = Parser

local function is_c0(byte)
  return byte <= 0x1f or byte == 0x7f
end

function Parser.new(emit, options)
  options = options or {}
  local action_emit = emit
  local print_sink
  if type(emit) == "table" then
    assert(type(emit.apply) == "function" and type(emit.write_codepoint) == "function", "parser state sink must implement apply and write_codepoint")
    print_sink = emit
    action_emit = function(action)
      emit:apply(action)
    end
  end
  local self = setmetatable({
    emit = assert(action_emit, "parser needs an action callback or terminal state sink"),
    print_sink = print_sink,
    mode = "ground",
    max_parameters = options.max_parameters or 32,
    max_parameter_value = options.max_parameter_value or 1000000,
    max_intermediates = options.max_intermediates or 4,
    max_string_bytes = options.max_string_bytes or 4096,
    stats = { bytes = 0, actions = 0, errors = 0, ignored = 0 },
  }, Parser)
  self.utf8 = Utf8.Decoder.new(function(codepoint, text, invalid)
    self:emit_print(codepoint, text, invalid)
  end)
  return self
end

function Parser:emit_action(action)
  self.stats.actions = self.stats.actions + 1
  self.emit(action)
end

function Parser:emit_print(codepoint, text, invalid)
  self.stats.actions = self.stats.actions + 1
  if self.print_sink then
    self.print_sink:write_codepoint(text, codepoint)
    return
  end
  self.emit(Actions.print(codepoint, text, invalid))
end

function Parser:reset_csi()
  self.parameters = {}
  self.current_parameter = nil
  self.seen_parameter = false
  self.private = ""
  self.intermediates = {}
  self.parameter_overflow = false
  self.colon = false
end

function Parser:reset_string(kind)
  self.string_kind = kind
  self.string_chunks = {}
  self.string_size = 0
  self.string_overflow = false
end

function Parser:enter_escape()
  self.mode = "escape"
  self.escape_intermediates = {}
end

function Parser:enter_csi()
  self.mode = "csi"
  self:reset_csi()
end

function Parser:enter_osc()
  self.mode = "osc"
  self:reset_string("osc")
end

function Parser:enter_dcs()
  self.mode = "dcs"
  self:reset_string("dcs")
end

function Parser:enter_ignore_string(kind)
  self.mode = "string"
  self:reset_string(kind)
end

function Parser:enter_apc()
  self.mode = "apc"
  self:reset_string("apc")
end

function Parser:append_string_byte(byte)
  if self.string_size >= self.max_string_bytes then
    self.string_overflow = true
    return
  end
  self.string_chunks[#self.string_chunks + 1] = string.char(byte)
  self.string_size = self.string_size + 1
end

function Parser:finish_osc()
  local payload = table.concat(self.string_chunks)
  self.mode = "ground"
  if self.string_overflow then
    self.stats.ignored = self.stats.ignored + 1
    self:emit_action(Actions.ignore("osc", "payload limit"))
    return
  end
  local command, value = payload:match("^(%d*);(.*)$")
  if command == nil then
    command, value = payload, ""
  end
  self:emit_action(Actions.osc(tonumber(command), value))
end

function Parser:finish_ignore_string(reason)
  local family = self.string_kind
  self.mode = "ground"
  self.stats.ignored = self.stats.ignored + 1
  self:emit_action(Actions.ignore(family, self.string_overflow and "payload limit" or reason or "unsupported"))
end

function Parser:finish_apc()
  local payload = table.concat(self.string_chunks)
  self.mode = "ground"
  if self.string_overflow then
    self.stats.ignored = self.stats.ignored + 1
    self:emit_action(Actions.ignore("apc", "payload limit"))
  elseif payload:sub(1, 1) == "G" then
    self:emit_action(Actions.apc(payload:sub(2)))
  else
    self.stats.ignored = self.stats.ignored + 1
    self:emit_action(Actions.ignore("apc", "unsupported"))
  end
end

function Parser:finish_dcs()
  local payload = table.concat(self.string_chunks)
  self.mode = "ground"
  if self.string_overflow then
    self.stats.ignored = self.stats.ignored + 1
    self:emit_action(Actions.ignore("dcs", "payload limit"))
  elseif payload:sub(1, 2) == "$q" then
    self:emit_action(Actions.dcs(payload:sub(3)))
  else
    self.stats.ignored = self.stats.ignored + 1
    self:emit_action(Actions.ignore("dcs", "unsupported"))
  end
end

function Parser:finish_csi(final)
  if self.current_parameter ~= nil or self.seen_parameter then
    if #self.parameters >= self.max_parameters then
      self.parameter_overflow = true
    else
      self.parameters[#self.parameters + 1] = self.current_parameter or 0
    end
  end
  self.mode = "ground"
  if self.parameter_overflow then
    self.stats.ignored = self.stats.ignored + 1
    self:emit_action(Actions.ignore("csi", "parameter limit"))
    return
  end
  self:emit_action(Actions.csi(self.parameters, self.private, table.concat(self.intermediates), string.char(final), self.colon))
end

function Parser:push_parameter()
  if #self.parameters >= self.max_parameters then
    self.parameter_overflow = true
    return
  end
  self.parameters[#self.parameters + 1] = self.current_parameter or 0
  self.current_parameter = nil
  self.seen_parameter = true
end

function Parser:push_intermediate(byte)
  if #self.intermediates >= self.max_intermediates then
    self.parameter_overflow = true
    return
  end
  self.intermediates[#self.intermediates + 1] = string.char(byte)
end

function Parser:handle_ground(byte)
  if byte == 0x1b then
    self:enter_escape()
  elseif byte == 0x9b then
    self:enter_csi()
  elseif byte == 0x9d then
    self:enter_osc()
  elseif byte == 0x90 then
    self:enter_dcs()
  elseif byte == 0x9f then
    self:enter_apc()
  elseif byte == 0x9e then
    self:enter_ignore_string("pm")
  elseif byte == 0x98 then
    self:enter_ignore_string("sos")
  elseif is_c0(byte) then
    self:emit_action(Actions.execute(byte))
  elseif byte >= 0x80 and byte <= 0x9f then
    self.stats.ignored = self.stats.ignored + 1
    self:emit_action(Actions.ignore("c1", string.format("0x%02x", byte)))
  else
    self.utf8:feed_byte(byte)
  end
end

function Parser:handle_escape(byte)
  if byte == 0x1b then
    self:enter_escape()
    return
  end
  if byte == 0x5b then
    self:enter_csi()
    return
  end
  if byte == 0x5d then
    self:enter_osc()
    return
  end
  if byte == 0x50 then
    self:enter_dcs()
    return
  end
  if byte == 0x5f then
    self:enter_apc()
    return
  end
  if byte == 0x5e then
    self:enter_ignore_string("pm")
    return
  end
  if byte == 0x58 then
    self:enter_ignore_string("sos")
    return
  end
  if byte >= 0x20 and byte <= 0x2f then
    if #self.escape_intermediates >= self.max_intermediates then
      self.mode = "ground"
      self.stats.errors = self.stats.errors + 1
      self:emit_action(Actions.ignore("esc", "intermediate limit"))
    else
      self.escape_intermediates[#self.escape_intermediates + 1] = string.char(byte)
    end
    return
  end
  if byte >= 0x30 and byte <= 0x7e then
    self.mode = "ground"
    self:emit_action(Actions.esc(string.char(byte), table.concat(self.escape_intermediates)))
    return
  end
  if is_c0(byte) then
    self:emit_action(Actions.execute(byte))
    return
  end
  self.mode = "ground"
  self.stats.errors = self.stats.errors + 1
  self:emit_action(Actions.ignore("esc", "malformed"))
end

function Parser:handle_csi(byte)
  if byte == 0x1b then
    self:enter_escape()
    return
  end
  if byte == 0x18 or byte == 0x1a then
    self.mode = "ground"
    self.stats.errors = self.stats.errors + 1
    self:emit_action(Actions.ignore("csi", "cancelled"))
    return
  end
  if is_c0(byte) then
    self:emit_action(Actions.execute(byte))
    return
  end
  if byte >= 0x30 and byte <= 0x39 then
    self.current_parameter = (self.current_parameter or 0) * 10 + (byte - 0x30)
    if self.current_parameter > self.max_parameter_value then
      self.parameter_overflow = true
      self.current_parameter = self.max_parameter_value
    end
    return
  end
  if byte == 0x3b then
    self:push_parameter()
    return
  end
  if byte == 0x3a then
    self.colon = true
    self:push_parameter()
    return
  end
  if byte >= 0x3c and byte <= 0x3f and #self.parameters == 0 and self.current_parameter == nil and self.private == "" then
    self.private = string.char(byte)
    return
  end
  if byte >= 0x20 and byte <= 0x2f then
    self:push_intermediate(byte)
    return
  end
  if byte >= 0x40 and byte <= 0x7e then
    self:finish_csi(byte)
    return
  end
  self.mode = "ground"
  self.stats.errors = self.stats.errors + 1
  self:emit_action(Actions.ignore("csi", "malformed"))
end

function Parser:handle_string(byte)
  if byte == 0x9c then
    self:finish_ignore_string()
  elseif byte == 0x1b then
    self.mode = "string_escape"
  else
    self:append_string_byte(byte)
  end
end

function Parser:handle_osc(byte)
  if byte == 0x07 or byte == 0x9c then
    self:finish_osc()
  elseif byte == 0x1b then
    self.mode = "osc_escape"
  else
    self:append_string_byte(byte)
  end
end

function Parser:handle_apc(byte)
  if byte == 0x9c then
    self:finish_apc()
  elseif byte == 0x1b then
    self.mode = "apc_escape"
  else
    self:append_string_byte(byte)
  end
end

function Parser:handle_dcs(byte)
  if byte == 0x9c then
    self:finish_dcs()
  elseif byte == 0x1b then
    self.mode = "dcs_escape"
  else
    self:append_string_byte(byte)
  end
end

function Parser:process_byte(byte)
  if self.mode == "ground" and self.utf8.remaining > 0 then
    if byte ~= 0x1b then
      self.utf8:feed_byte(byte)
      return
    end
    self.utf8:finish()
  end
  if self.mode == "ground" then
    self:handle_ground(byte)
  elseif self.mode == "escape" then
    self:handle_escape(byte)
  elseif self.mode == "csi" then
    self:handle_csi(byte)
  elseif self.mode == "osc" then
    self:handle_osc(byte)
  elseif self.mode == "apc" then
    self:handle_apc(byte)
  elseif self.mode == "dcs" then
    self:handle_dcs(byte)
  elseif self.mode == "string" then
    self:handle_string(byte)
  elseif self.mode == "osc_escape" then
    if byte == 0x5c then
      self:finish_osc()
    else
      self.stats.errors = self.stats.errors + 1
      self.mode = "ground"
      self:emit_action(Actions.ignore("osc", "malformed terminator"))
      self:process_byte(byte)
    end
  elseif self.mode == "string_escape" then
    if byte == 0x5c then
      self:finish_ignore_string()
    else
      self.stats.errors = self.stats.errors + 1
      self.mode = "ground"
      self:emit_action(Actions.ignore(self.string_kind, "malformed terminator"))
      self:process_byte(byte)
    end
  elseif self.mode == "apc_escape" then
    if byte == 0x5c then
      self:finish_apc()
    else
      self.stats.errors = self.stats.errors + 1
      self.mode = "ground"
      self:emit_action(Actions.ignore("apc", "malformed terminator"))
      self:process_byte(byte)
    end
  elseif self.mode == "dcs_escape" then
    if byte == 0x5c then
      self:finish_dcs()
    else
      self.stats.errors = self.stats.errors + 1
      self.mode = "ground"
      self:emit_action(Actions.ignore("dcs", "malformed terminator"))
      self:process_byte(byte)
    end
  end
end

function Parser:feed(bytes)
  assert(type(bytes) == "string", "parser input must be a byte string")
  for index = 1, #bytes do
    self.stats.bytes = self.stats.bytes + 1
    self:process_byte(bytes:byte(index))
  end
end

function Parser:finish()
  if self.mode == "ground" then
    self.utf8:finish()
    return
  end
  local family = self.mode == "csi" and "csi" or self.mode == "escape" and "esc" or self.string_kind or "osc"
  self.mode = "ground"
  self.stats.errors = self.stats.errors + 1
  self:emit_action(Actions.ignore(family, "truncated"))
end

return Parser
