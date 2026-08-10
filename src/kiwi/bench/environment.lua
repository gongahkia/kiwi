local jit = require("jit")

local Environment = {}

local function file_text(path)
  local file = io.open(path, "r")
  if not file then
    return "unavailable"
  end
  local output = file:read("*a")
  file:close()
  output = output:gsub("%s+$", "")
  return #output > 0 and output or "unavailable"
end

local function command_output(command)
  local handle = io.popen(command, "r")
  if not handle then
    return "unavailable"
  end
  local output = handle:read("*a")
  local ok = handle:close()
  if not ok then
    return "unavailable"
  end
  output = output:gsub("%s+$", "")
  return #output > 0 and output or "unavailable"
end

local function jit_features()
  local status = { jit.status() }
  local features = {}
  for index = 2, #status do
    features[#features + 1] = status[index]
  end
  return {
    enabled = status[1] == true,
    features = features,
  }
end

function Environment.collect(timestamp, iterations, warmup)
  local dirty = command_output("git diff --quiet --ignore-submodules --; printf '%s' $?")
  return {
    timestamp_utc = timestamp,
    revision = {
      branch = command_output("git branch --show-current"),
      commit = command_output("git rev-parse --verify --short HEAD"),
      dirty = dirty == "1",
    },
    system = {
      architecture = jit.arch,
      cpu_model = command_output("sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1"),
      cpu_affinity = command_output("taskset -pc $$ | sed 's/.*: //'"),
      cpu_governor = file_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
      gl_renderer = command_output("glxinfo -B 2>/dev/null | sed -n 's/^OpenGL renderer string: //p' | head -n 1"),
      gl_version = command_output("glxinfo -B 2>/dev/null | sed -n 's/^OpenGL core profile version string: //p' | head -n 1"),
      kernel = command_output("uname -srm"),
      operating_system = jit.os,
      vulkan_gpu0 = command_output("vulkaninfo --summary 2>/dev/null | sed -n 's/^[[:space:]]*deviceName[[:space:]]*=[[:space:]]*//p' | head -n 1"),
      vulkan_gpu0_driver = command_output("vulkaninfo --summary 2>/dev/null | sed -n 's/^[[:space:]]*driverInfo[[:space:]]*=[[:space:]]*//p' | head -n 1"),
    },
    runtime = {
      compiler_flags = os.getenv("CFLAGS") or "not provided; LuaJIT default JIT configuration",
      jit = jit_features(),
      luajit_version = jit.version,
      lua_version = _VERSION,
    },
    configuration = {
      iterations = iterations,
      warmup_iterations = warmup,
    },
    methodology = {
      clock = "os.clock process CPU time",
      cpu_scope = "Lua byte/UTF-8 scanning, parser, terminal state, damage, and CPU instance packing as named by each component; GPU submission and presentation are excluded",
      memory = "Lua heap retained and peak deltas in KiB after an explicit collection; allocator-sensitive diagnostic signal",
      warmup = "warm-up iterations run with identical setup and are excluded from timing summaries",
    },
  }
end

return Environment
