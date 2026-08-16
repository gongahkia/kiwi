local Actions = {}

function Actions.print(codepoint, text, invalid)
  return { kind = "print", codepoint = codepoint, text = text, invalid_utf8 = invalid }
end

function Actions.execute(code)
  return { kind = "execute", code = code }
end

function Actions.esc(final, intermediates)
  return { kind = "esc", final = final, intermediates = intermediates or "" }
end

function Actions.csi(parameters, private, intermediates, final, colon)
  return {
    kind = "csi",
    parameters = parameters,
    private = private or "",
    intermediates = intermediates or "",
    final = final,
    colon = colon or false,
  }
end

function Actions.osc(command, payload)
  return { kind = "osc", command = command, payload = payload }
end

function Actions.apc(payload)
  return { kind = "apc", payload = payload }
end

function Actions.dcs(payload)
  return { kind = "dcs", payload = payload }
end

function Actions.xtgettcap(payload)
  return { kind = "xtgettcap", payload = payload }
end

function Actions.ignore(family, reason)
  return { kind = "ignore", family = family, reason = reason }
end

return Actions
