local ShellIntegration = {}

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function readable(path)
  local handle = io.open(path, "rb")
  if handle == nil then return false end
  handle:close()
  return true
end

local function copy_command(command)
  local copy = {}
  for index, value in ipairs(command) do copy[index] = value end
  return copy
end

local function environment_value(environment, name)
  if environment then return environment(name) end
  return os.getenv(name)
end

local function nushell_source_command(path)
  if type(path) ~= "string" or path:find("\0", 1, true) or path:find("\r", 1, true) or path:find("\n", 1, true) then return nil end
  path = path:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\t", "\\t")
  return 'source "' .. path .. '"'
end

local function integration_environment(directory, script, environment)
  return {
    KIWI_SHELL_INTEGRATION = "1",
    KIWI_SHELL_INTEGRATION_SCRIPT = directory .. "/" .. script,
    KIWI_SHELL_INTEGRATION_ORIGINAL_BASHRC = environment_value(environment, "HOME") and environment_value(environment, "HOME") .. "/.bashrc" or false,
    KIWI_SHELL_INTEGRATION_ORIGINAL_ZDOTDIR = environment_value(environment, "ZDOTDIR") or environment_value(environment, "HOME") or false,
    KIWI_SHELL_INTEGRATION_INJECT_DIR = directory .. "/inject/zsh",
  }
end

-- Prepares only Kiwi's initial default shell. It leaves explicit commands and
-- shells started from within the terminal alone, so users retain a reversible
-- manual path for those cases.
function ShellIntegration.prepare(command, directory, environment)
  assert(type(command) == "table" and #command == 1 and type(command[1]) == "string", "shell integration needs one default-shell command")
  assert(type(directory) == "string" and #directory > 0, "shell integration needs an integration directory")
  local shell = basename(command[1])
  local script = "kiwi." .. shell
  if shell == "bash" then
    if not readable(directory .. "/" .. script) or not readable(directory .. "/inject/kiwi.bashrc") then
      return copy_command(command), {}, "resources-unavailable"
    end
    return { command[1], "--rcfile", directory .. "/inject/kiwi.bashrc", "-i" }, integration_environment(directory, script, environment), nil
  end
  if shell == "fish" then
    if not readable(directory .. "/" .. script) then return copy_command(command), {}, "resources-unavailable" end
    return { command[1], "--init-command", "source $KIWI_SHELL_INTEGRATION_SCRIPT", "-i" }, integration_environment(directory, script, environment), nil
  end
  if shell == "zsh" then
    if not readable(directory .. "/" .. script) or not readable(directory .. "/inject/zsh/.zshenv") or not readable(directory .. "/inject/zsh/.zshrc") then
      return copy_command(command), {}, "resources-unavailable"
    end
    local original = environment_value(environment, "ZDOTDIR") or environment_value(environment, "HOME")
    if type(original) ~= "string" or #original == 0 then return copy_command(command), {}, "home-unavailable" end
    local values = integration_environment(directory, script, environment)
    values.ZDOTDIR = values.KIWI_SHELL_INTEGRATION_INJECT_DIR
    return { command[1], "-i" }, values, nil
  end
  if shell == "nu" then
    if not readable(directory .. "/" .. script) then return copy_command(command), {}, "resources-unavailable" end
    local source_command = nushell_source_command(directory .. "/" .. script)
    if source_command == nil then return copy_command(command), {}, "invalid-resource-path" end
    return { command[1], "--execute", source_command, "--interactive" }, integration_environment(directory, script, environment), nil
  end
  return copy_command(command), {}, "unsupported-shell"
end

return ShellIntegration
