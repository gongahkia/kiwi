local Snapshot = {}

local function quote(value)
  local encoded = { '"' }
  for index = 1, #value do
    local byte = value:byte(index)
    if byte == string.byte('"') or byte == string.byte("\\") then
      encoded[#encoded + 1] = "\\" .. string.char(byte)
    elseif byte == 0x0A then
      encoded[#encoded + 1] = "\\n"
    elseif byte == 0x0D then
      encoded[#encoded + 1] = "\\r"
    elseif byte == 0x09 then
      encoded[#encoded + 1] = "\\t"
    elseif byte < 0x20 or byte == 0x7F then
      encoded[#encoded + 1] = string.format("\\x%02X", byte)
    else
      encoded[#encoded + 1] = string.char(byte)
    end
  end
  encoded[#encoded + 1] = '"'
  return table.concat(encoded)
end

local function colour(value)
  if value == "default" then
    return "default"
  end
  if value.kind == "indexed" then
    return "indexed:" .. value.index
  end
  return "rgb:" .. value.red .. "," .. value.green .. "," .. value.blue
end

local function cell(cell)
  return table.concat({
    "text=" .. quote(cell.text),
    "width=" .. cell.width,
    "continuation=" .. tostring(cell.continuation),
    "attributes=" .. cell.attributes,
    "foreground=" .. colour(cell.foreground),
    "background=" .. colour(cell.background),
  }, ",")
end

local function append_rows(lines, name, screen)
  lines[#lines + 1] = name
  for index, row in ipairs(screen.rows) do
    local cells = {}
    for column = 1, row.columns do
      cells[column] = "{" .. cell(row.cells[column]) .. "}"
    end
    lines[#lines + 1] = "  "
      .. index
      .. ": wrapped="
      .. tostring(row.wrapped)
      .. "; cells="
      .. table.concat(cells, " ")
  end
end

local function cursor(name, value)
  return name
    .. "=row:"
    .. value.row
    .. ",column:"
    .. value.column
    .. ",pending_wrap:"
    .. tostring(value.pending_wrap)
end

local function rendition(name, value)
  return name
    .. "=attributes:"
    .. value.attributes
    .. ",foreground:"
    .. colour(value.foreground)
    .. ",background:"
    .. colour(value.background)
end

local function tab_stops(tab_stops, columns)
  local values = {}
  for column = 1, columns do
    if tab_stops[column] then
      values[#values + 1] = column
    end
  end
  return table.concat(values, ",")
end

local function append_scrollback(lines, scrollback)
  lines[#lines + 1] = "scrollback_tail"
  lines[#lines + 1] = "  limit=" .. scrollback.limit .. ",count=" .. scrollback.count
  for index = 1, scrollback.count do
    local row = assert(scrollback:at(index))
    local cells = {}
    for column = 1, row.columns do
      cells[column] = "{" .. cell(row.cells[column]) .. "}"
    end
    lines[#lines + 1] = "  "
      .. index
      .. ": wrapped="
      .. tostring(row.wrapped)
      .. "; cells="
      .. table.concat(cells, " ")
  end
end

local function append_diagnostics(lines, diagnostics)
  lines[#lines + 1] = "unsupported_events"
  if #diagnostics == 0 then
    lines[#lines + 1] = "  none"
    return
  end
  for index, event in ipairs(diagnostics) do
    if event.kind == "unsupported_sequence" and event.sequence_kind == "csi" then
      lines[#lines + 1] = "  "
        .. index
        .. ": unsupported csi final="
        .. quote(string.char(event.final))
        .. ",parameters="
        .. quote(event.parameters)
        .. ",intermediates="
        .. quote(event.intermediates)
    elseif event.kind == "unsupported_sequence" and event.sequence_kind == "osc" then
      lines[#lines + 1] = "  "
        .. index
        .. ": unsupported osc payload="
        .. quote(event.payload)
        .. ",terminator="
        .. event.terminator
    elseif event.kind == "unsupported_sequence" and event.sequence_kind == "esc" then
      lines[#lines + 1] = "  "
        .. index
        .. ": unsupported esc final="
        .. quote(string.char(event.final))
        .. ",intermediates="
        .. quote(event.intermediates)
    else
      lines[#lines + 1] = "  "
        .. index
        .. ": malformed reason="
        .. event.reason
        .. ",state="
        .. event.state
        .. ",byte="
        .. event.byte
    end
  end
end

function Snapshot.render(terminal, diagnostics)
  local parser = terminal.parser:snapshot()
  local utf8 = terminal.utf8_decoder:snapshot()
  local lines = {
    "profile=" .. terminal.config.compatibility_profile,
    "size=" .. terminal.config.columns .. "x" .. terminal.config.rows,
    "active_buffer=" .. terminal.active_buffer,
    cursor("cursor", terminal.cursor),
    cursor("saved_cursor", terminal.saved_cursor),
    "modes=auto_wrap:" .. tostring(terminal.modes.auto_wrap) .. ",cursor_visible:" .. tostring(
      terminal.modes.cursor_visible
    ),
    "margins=top:" .. terminal.margins.top .. ",bottom:" .. terminal.margins.bottom,
    rendition("rendition", terminal.rendition),
    rendition("saved_rendition", terminal.saved_rendition),
    "tab_stops=" .. tab_stops(terminal.tab_stops, terminal.config.columns),
  }
  append_rows(lines, "primary_rows", terminal.primary_screen)
  append_rows(lines, "alternate_rows", terminal.alternate_screen)
  append_scrollback(lines, terminal.scrollback)
  lines[#lines + 1] = "parser_state=" .. parser.state .. ",byte_offset=" .. parser.byte_offset
  lines[#lines + 1] = "parser_buffers=csi_intermediates="
    .. quote(parser.csi_intermediates)
    .. ",csi_parameters="
    .. quote(parser.csi_parameters)
    .. ",escape_intermediates="
    .. quote(parser.escape_intermediates)
    .. ",osc_payload="
    .. quote(parser.osc_payload)
  lines[#lines + 1] = "parser_limits=max_csi_bytes:"
    .. parser.max_csi_bytes
    .. ",max_escape_intermediate_bytes:"
    .. parser.max_escape_intermediate_bytes
    .. ",max_osc_bytes:"
    .. parser.max_osc_bytes
  lines[#lines + 1] = "utf8_state=codepoint:"
    .. utf8.codepoint
    .. ",minimum:"
    .. utf8.minimum
    .. ",remaining:"
    .. utf8.remaining
  append_diagnostics(lines, diagnostics)
  return table.concat(lines, "\n") .. "\n"
end

return Snapshot
