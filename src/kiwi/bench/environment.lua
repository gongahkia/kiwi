local jit = require("jit")
local Runtime = require("kiwi.runtime")

local Environment = {}

-- Call only after the timed workload has exited. This observes retained traces,
-- not historical flushes, and installs no trace/profiler callbacks. Scan across
-- holes left by collected traces; stored LuaJIT trace numbers are 16-bit.
function Environment.jit_snapshot()
  local util = require("jit.util")
  local result = { traces = 0, maximum_trace = 0, machine_code_bytes = 0,
    ir_instructions = 0, scan_limit = 65535, observation = "after workload exit" }
  for number = 1, result.scan_limit do
    local info = util.traceinfo(number)
    if info then
      result.traces = result.traces + 1
      result.maximum_trace = number
      result.ir_instructions = result.ir_instructions + info.nins
      local code = util.tracemc(number)
      if code then result.machine_code_bytes = result.machine_code_bytes + #code end
    end
  end
  return result
end
-- Inspection must not compile its own enumeration loop or alter JIT mode.
jit.off(Environment.jit_snapshot)

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

function Environment.revision()
  local commit = command_output("git rev-parse --verify HEAD 2>/dev/null")
  local archived = commit == "unavailable"
  local revision = {
    branch = archived and "archive" or command_output("git branch --show-current"),
    commit = archived and file_text("BUILD_REVISION") or commit,
    source = archived and "BUILD_REVISION" or "git",
  }
  if not archived then
    -- Include staged and untracked sources. A failed status command must not
    -- attest a clean tree and admit misleading baseline comparisons.
    revision.dirty = command_output("git status --porcelain=v1 --untracked-files=normal && printf 'KIWI_SOURCE_STATUS_OK\\n'") ~= "KIWI_SOURCE_STATUS_OK"
  end
  return revision
end

function Environment.collect(timestamp, iterations, warmup)
  local revision = Environment.revision()
  local macos = jit.os == "OSX"
  return {
    timestamp_utc = timestamp,
    revision = revision,
    system = {
      architecture = jit.arch,
      cpu_model = macos and command_output("sysctl -n machdep.cpu.brand_string 2>/dev/null") or command_output("sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo | head -n 1"),
      cpu_affinity = macos and "unavailable" or command_output("taskset -pc $$ | sed 's/.*: //'"),
      cpu_governor = macos and "unavailable" or file_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
      cgroup_cpu_limit = macos and "not applicable" or file_text("/sys/fs/cgroup/cpu.max"),
      cgroup_memory_limit = macos and "not applicable" or file_text("/sys/fs/cgroup/memory.max"),
      gl_renderer = command_output("glxinfo -B 2>/dev/null | sed -n 's/^OpenGL renderer string: //p' | head -n 1"),
      gl_version = command_output("glxinfo -B 2>/dev/null | sed -n 's/^OpenGL core profile version string: //p' | head -n 1"),
      kernel = command_output("uname -srm"),
      operating_system = jit.os,
      vulkan_gpu0 = command_output("vulkaninfo --summary 2>/dev/null | sed -n 's/^[[:space:]]*deviceName[[:space:]]*=[[:space:]]*//p' | head -n 1"),
      vulkan_gpu0_driver = command_output("vulkaninfo --summary 2>/dev/null | sed -n 's/^[[:space:]]*driverInfo[[:space:]]*=[[:space:]]*//p' | head -n 1"),
    },
    runtime = {
      compiler_flags = os.getenv("CFLAGS") or "not provided",
      machine_code_limit_kib = Runtime.machine_code_limit_kib,
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

function Environment.collect_pacing(timestamp, measurement)
  local environment = Environment.collect(timestamp, measurement.sample_limit, measurement.warmup_frames)
  local session = jit.os == "OSX" and "cocoa" or os.getenv("WAYLAND_DISPLAY") and "wayland" or os.getenv("DISPLAY") and "x11" or "unavailable"
  environment.configuration = {
    sample_limit = measurement.sample_limit,
    warmup_frames = measurement.warmup_frames,
    pty_read_budget = measurement.pty_read_budget,
    present_mode = "fifo",
  }
  environment.methodology = {
    clock = "GLFW monotonic time; not os.clock",
    scope = "terminal PTY event to successful Renderer:render return; no GPU execution, compositor, or panel latency claim",
    samples = "bounded aggregate summaries; event payloads are not retained",
  }
  environment.system.display_session = session
  environment.system.display_refresh_hz = command_output("xrandr --current 2>/dev/null | awk '/\\*/ { for (i = 1; i <= NF; ++i) if ($i ~ /\\*$/) { sub(/\\*$/, \"\", $i); print $i; exit } }'")
  environment.system.power_profile = command_output("powerprofilesctl get 2>/dev/null | head -n 1")
  environment.system.scheduler_nice = command_output("ps -o ni= -p $$ | tr -d ' '")
  return environment
end

return Environment
