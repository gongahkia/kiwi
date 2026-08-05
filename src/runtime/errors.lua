local Errors = {}

Errors.contract = {
  new = "new(kind, message, detail?) -> error | nil, error",
  is = "is(value) -> boolean",
}

local known_kinds = {
  backend_exited = true,
  backend_protocol_error = true,
  backend_unavailable = true,
  config_error = true,
  effect_load_error = true,
  effect_incompatible = true,
  effect_reload_error = true,
  effect_runtime_error = true,
  internal_invariant_error = true,
  parser_error = true,
  recording_corrupt = true,
  recording_io_error = true,
  recording_unsupported_version = true,
  renderer_resource_error = true,
  sandbox_command_error = true,
}

function Errors.new(kind, message, detail)
  if not known_kinds[kind] then
    return nil,
      {
        kind = "internal_invariant_error",
        message = "unknown error kind",
        detail = { provided_kind = kind },
      }
  end
  if type(message) ~= "string" or message == "" then
    return nil,
      {
        kind = "internal_invariant_error",
        message = "error message must be a non-empty string",
        detail = { provided_kind = kind },
      }
  end
  return {
    kind = kind,
    message = message,
    detail = detail,
  }
end

function Errors.is(value)
  return type(value) == "table"
    and known_kinds[value.kind] == true
    and type(value.message) == "string"
end

return Errors
