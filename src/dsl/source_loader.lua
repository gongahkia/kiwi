local source_loader = { DEFAULT_FIXTURE = "initial_policy" }

local fixtures = {
  initial_policy = "content/doctrines/initial_policy.dsl",
}

function source_loader.load(identifier, read_file)
  local path = fixtures[identifier]
  if not path then
    return nil, { code = "unknown_source_fixture", message = "source fixture is not registered" }
  end
  if type(read_file) ~= "function" then
    return nil, { code = "invalid_source_reader", message = "source reader must be a function" }
  end

  local ok, source, read_error = pcall(read_file, path)
  if not ok or type(source) ~= "string" then
    return nil,
      {
        code = "source_read_failed",
        message = "could not read source fixture: " .. tostring(ok and read_error or source),
      }
  end
  if source == "" then
    return nil, { code = "empty_source_fixture", message = "source fixture cannot be empty" }
  end
  return source
end

return source_loader
