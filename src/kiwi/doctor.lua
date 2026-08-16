local Build = require("kiwi.build")
local Json = require("kiwi.bench.json")

local Doctor = {
  MAX_BUNDLE_BYTES = 64 * 1024,
  MAX_VALUE_BYTES = 256,
  SCHEMA_VERSION = 1,
}

local function bounded(value, maximum)
  value = tostring(value or "")
  maximum = maximum or Doctor.MAX_VALUE_BYTES
  if #value <= maximum then return value end
  return value:sub(1, maximum) .. " [truncated]"
end

local function unavailable(reason)
  return { status = "unavailable", reason = reason }
end

local function count_csv(value)
  if type(value) ~= "string" or #value == 0 then return 0 end
  local count = 0
  for _ in value:gmatch("[^,]+") do count = count + 1 end
  return count
end

local function default_command(command)
  local process = io.popen(command, "r")
  if not process then return nil end
  local value = process:read("*a")
  process:close()
  value = value:gsub("[\r\n]+$", "")
  return bounded(value)
end

local function default_path_exists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  return false
end

local function session_kind(getenv)
  if getenv("WAYLAND_DISPLAY") then return "wayland" end
  if getenv("DISPLAY") then return "x11" end
  return "unavailable"
end

local function configuration(getenv)
  return {
    extensions = {
      configured = getenv("KIWI_RENDER_EXTENSIONS") ~= nil and #getenv("KIWI_RENDER_EXTENSIONS") > 0,
      requested_count = count_csv(getenv("KIWI_RENDER_EXTENSIONS")),
      safe_mode = getenv("KIWI_SAFE_MODE") == "1",
    },
    features = {
      command_regions = getenv("KIWI_COMMAND_REGIONS") == "1",
      contextual_alternates = getenv("KIWI_CALT") == "1",
      ligatures = getenv("KIWI_LIGATURES") == "1",
      text_backend_requested = getenv("KIWI_TEXT_BACKEND") ~= nil,
    },
    fonts = {
      custom_family_configured = getenv("KIWI_FONT_FAMILY") ~= nil,
      custom_path_configured = getenv("KIWI_FONT") ~= nil,
      pixel_size = bounded(getenv("KIWI_FONT_PX") or "default", 32),
    },
    terminal = {
      ambiguous_width = bounded(getenv("KIWI_AMBIGUOUS_WIDTH") or "1", 32),
      scrollback_lines = bounded(getenv("KIWI_SCROLLBACK") or "2000", 32),
      term = "kiwi",
    },
  }
end

local function default_gpu_probe(getenv)
  if session_kind(getenv) == "unavailable" then
    return unavailable("no Wayland or X11 display is available")
  end

  local window
  local context
  local ok, result = xpcall(function()
    local Window = require("kiwi.platform.window")
    local Context = require("kiwi.gpu.context")
    window = Window.new(1, 1, "Kiwi doctor", { release_mode = true, visible = false })
    context = Context.new(window)
    return {
      adapter = {
        backend = bounded(context.adapter_info.backend_name),
        device = bounded(context.adapter_info.device),
        vendor = bounded(context.adapter_info.vendor),
      },
      capabilities = {
        timestamp_query = (function()
          local status = context:timestamp_status()
          status.reason = bounded(status.reason)
          return status
        end)(),
      },
      status = "available",
    }
  end, debug.traceback)
  if context then context:destroy() end
  if window then window:destroy() end
  if not ok then return unavailable("native adapter initialization failed") end
  return result
end

function Doctor.collect(options)
  options = options or {}
  local getenv = options.getenv or os.getenv
  local build = options.build or Build.info({ getenv = getenv, root = options.root })
  local command = options.command or default_command
  local path_exists = options.path_exists or default_path_exists
  local gpu_probe = options.gpu_probe or default_gpu_probe
  local root = options.root or getenv("KIWI_ROOT") or "."
  local session = session_kind(getenv)
  local terminfo_available = path_exists(root .. "/.build/terminfo") or path_exists(root .. "/share/terminfo")
  local jit = rawget(_G, "jit") or {}

  return {
    build = {
      release_mode = build.release_mode == true,
      revision = bounded(build.revision),
      version = bounded(build.version),
    },
    configuration = configuration(getenv),
    environment = {
      architecture = bounded(jit.arch or "unavailable"),
      kernel = command("uname -sr") or "unavailable",
      lua = bounded(jit.version or _VERSION),
      operating_system = bounded(jit.os or "unavailable"),
      session = session,
    },
    gpu = gpu_probe(getenv),
    privacy = {
      bundle_maximum_bytes = Doctor.MAX_BUNDLE_BYTES,
      clipboard_content = "excluded",
      environment_values = "allowlisted summary only",
      network = "not used",
      recent_diagnostic_history = "not persisted",
      shell_content = "excluded",
      terminal_content = "excluded",
    },
    renderer = {
      pass_state = unavailable("doctor does not attach to a live terminal session"),
      status = "not-running",
    },
    schema_version = Doctor.SCHEMA_VERSION,
    terminal = {
      feature_state = unavailable("no live terminal session is attached"),
      known_features = {
        accessibility_adapter = unavailable("Linux AT-SPI is optional and doctor does not attach to a live accessibility bus; macOS and Windows adapters are unimplemented"),
        clipboard = { maximum_bytes = 1024 * 1024, status = "available" },
        kitty_graphics = { status = "available" },
        shell_integration = { status = "available" },
        truecolour_terminfo = unavailable("Kiwi advertises 16 colours and does not set COLORTERM"),
      },
      terminfo = terminfo_available and { status = "available" } or unavailable("Kiwi terminfo is not built or installed"),
    },
  }
end

function Doctor.encode(report)
  local encoded = Json.encode(report)
  assert(#encoded <= Doctor.MAX_BUNDLE_BYTES, "doctor bundle exceeds the fixed maximum size")
  return encoded
end

function Doctor.format(report)
  local gpu = report.gpu or unavailable("not probed")
  local adapter = gpu.adapter or {}
  local timestamp = gpu.capabilities and gpu.capabilities.timestamp_query or {}
  return table.concat({
    "Kiwi doctor",
    string.format("build: version=%s revision=%s mode=%s", report.build.version, report.build.revision, report.build.release_mode and "release" or "development"),
    string.format("environment: os=%s arch=%s kernel=%s session=%s lua=%s", report.environment.operating_system, report.environment.architecture, report.environment.kernel, report.environment.session, report.environment.lua),
    string.format("gpu: status=%s backend=%s vendor=%s adapter=%s timestamp-query=%s", gpu.status, adapter.backend or "unavailable", adapter.vendor or "unavailable", adapter.device or "unavailable", timestamp.reason or gpu.reason or "unavailable"),
    string.format("terminal: terminfo=%s live-state=%s", report.terminal.terminfo.status, report.terminal.feature_state.status),
    string.format("renderer: status=%s pass-state=%s", report.renderer.status, report.renderer.pass_state.status),
    string.format("privacy: network=%s terminal=%s clipboard=%s shell=%s maximum-bundle-bytes=%d", report.privacy.network, report.privacy.terminal_content, report.privacy.clipboard_content, report.privacy.shell_content, report.privacy.bundle_maximum_bytes),
  }, "\n")
end

function Doctor.write_bundle(path, report)
  assert(type(path) == "string" and #path > 0 and not path:find("\0", 1, true), "doctor bundle path must be a non-empty NUL-free string")
  local file, message = io.open(path, "wb")
  assert(file, "unable to write doctor bundle: " .. tostring(message))
  file:write(Doctor.encode(report), "\n")
  file:close()
end

local function parse_options(arguments)
  local options = { format = "human" }
  local index = 1
  while index <= #arguments do
    local value = arguments[index]
    if value == "--json" then
      options.format = "json"
    elseif value == "--bundle" then
      index = index + 1
      options.bundle = assert(arguments[index], "--bundle needs a path")
    else
      error("unknown doctor option: " .. value .. "; use --json and/or --bundle PATH")
    end
    index = index + 1
  end
  return options
end

function Doctor.main(arguments)
  local options = parse_options(arguments or arg)
  local report = Doctor.collect()
  if options.bundle then
    Doctor.write_bundle(options.bundle, report)
    io.stderr:write("Kiwi doctor bundle: ", options.bundle, "\n")
  end
  if options.format == "json" then
    io.stdout:write(Doctor.encode(report), "\n")
  else
    io.stdout:write(Doctor.format(report), "\n")
  end
end

if ... ~= "kiwi.doctor" then Doctor.main(arg) end

return Doctor
