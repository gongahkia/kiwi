local ffi = require("ffi")
local Environment = require("kiwi.bench.environment")
local Json = require("kiwi.bench.json")
local Parser = require("kiwi.terminal.parser")
local Pty = require("kiwi.process.pty")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")
local Stats = require("kiwi.bench.stats")
local Utf8 = require("kiwi.terminal.utf8")

ffi.cdef[[
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int clock_id, struct timespec *tp);
]]

local clock_ids = {
  Linux = 1,
  OSX = 6,
}
local clock_monotonic = assert(clock_ids[ffi.os], "real-PTY burst benchmark requires a supported monotonic clock")
local clock_description = "clock_gettime(CLOCK_MONOTONIC) monotonic wall time"

local function monotonic_seconds()
  local value = ffi.new("struct timespec[1]")
  assert(ffi.C.clock_gettime(clock_monotonic, value) == 0, "clock_gettime(CLOCK_MONOTONIC) failed")
  return tonumber(value[0].tv_sec) + tonumber(value[0].tv_nsec) / 1000000000
end

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value > 0 and math.floor(value) or fallback
end

local function resident_kib()
  local file = io.open("/proc/self/status", "r")
  if not file then
    return nil
  end
  for line in file:lines() do
    local value = line:match("^VmRSS:%s+(%d+)%s+kB$")
    if value then
      file:close()
      return tonumber(value)
    end
  end
  file:close()
  return nil
end

local function expected_snapshot(input)
  local state = State.new(80, 24, { scrollback_limit = 256 })
  state.damage:clear()
  local parser = Parser.new(state)
  parser:feed(input)
  parser:finish()
  return Snapshot.encode(state)
end

local function run_case(case, read_budget, max_service_ms, max_heap_kib)
  local expected = case.reference_input and expected_snapshot(case.reference_input) or nil
  collectgarbage("collect")
  local heap_before = collectgarbage("count")
  local rss_before = resident_kib()
  local pty = Pty.spawn(case.command, 80, 24, { TERM = "xterm-kiwi", COLORTERM = "truecolor" })
  local state = State.new(80, 24, { scrollback_limit = 256 })
  state.damage:clear()
  local parser = Parser.new(state)
  local bytes = 0
  local service_iterations = 0
  local active_service_iterations = 0
  local max_service = 0
  local service_samples = {}
  local frame_deadline_slots = 0
  local started = monotonic_seconds()
  local next_frame_deadline = started
  local deadline = started + 90
  local status

  while true do
    local service_started = monotonic_seconds()
    local output = pty:read_available(read_budget)
    assert(#output <= read_budget, "PTY read exceeded its configured budget")
    if #output > 0 then
      bytes = bytes + #output
      parser:feed(output)
      active_service_iterations = active_service_iterations + 1
    end
    local responses = state:pop_responses()
    if #responses > 0 then
      pty:enqueue(table.concat(responses))
    end
    pty:flush()
    status = pty:poll_exit()
    local service_finished = monotonic_seconds()
    service_iterations = service_iterations + 1
    local service_ms = (service_finished - service_started) * 1000
    service_samples[#service_samples + 1] = service_ms
    max_service = math.max(max_service, service_ms)
    if #output > 0 then
      while service_finished >= next_frame_deadline do
        frame_deadline_slots = frame_deadline_slots + 1
        next_frame_deadline = next_frame_deadline + 1 / 30
      end
    end
    if status and pty.eof then
      break
    end
    assert(service_finished < deadline, case.name .. " PTY burst timed out")
    ffi.C.usleep(1000)
  end
  parser:finish()
  pty:shutdown()
  local elapsed_ms = (monotonic_seconds() - started) * 1000
  collectgarbage("collect")
  local heap_after = collectgarbage("count")
  local rss_after = resident_kib()
  local result = {
    name = case.name,
    expected_minimum_bytes = case.minimum_bytes,
    bytes_read = bytes,
    service_iterations = service_iterations,
    active_service_iterations = active_service_iterations,
    max_service_ms = max_service,
    service_ms = Stats.summary(service_samples),
    elapsed_wall_ms = elapsed_ms,
    frame_deadline_slots_serviced_while_output_active = frame_deadline_slots,
    final_snapshot = Snapshot.encode(state),
    parser = parser.stats,
    responses_written = pty.bytes_written,
    memory = {
      heap_kib_delta = heap_after - heap_before,
      rss_kib_delta = rss_before and rss_after and rss_after - rss_before or nil,
    },
  }
  assert(status.kind == "exit" and status.code == 0, case.name .. " child did not exit successfully")
  assert(bytes >= case.minimum_bytes, case.name .. " output was truncated")
  assert(max_service <= max_service_ms, string.format("%s service turn %.3fms exceeded %.3fms", case.name, max_service, max_service_ms))
  assert(result.memory.heap_kib_delta <= max_heap_kib, string.format("%s retained Lua heap %.1f KiB exceeded %d KiB", case.name, result.memory.heap_kib_delta, max_heap_kib))
  if expected then
    assert(result.final_snapshot == expected, case.name .. " final canonical snapshot diverged")
  end
  if case.expect_responses then
    assert(result.responses_written > 0, case.name .. " terminal response was starved")
  end
  return result
end

local mib = 1024 * 1024
local mixed_unit = "\27[31mKiwi\27[0m\r\n"
local mixed_repetitions = math.ceil(mib / #mixed_unit)
local unicode_unit = "Cafe" .. Utf8.encode(0x0301) .. " " .. Utf8.encode(0x4e2d) .. " "
  .. Utf8.encode(0x1f469) .. Utf8.encode(0x200d) .. Utf8.encode(0x1f680) .. " " .. Utf8.encode(0xe0b0) .. "\n"
local unicode_pty_unit = unicode_unit:gsub("\n", "\r\n")
local unicode_repetitions = math.ceil((128 * 1024) / #unicode_unit)
local cases = {
  {
    name = "printable-1mib",
    command = { "/bin/sh", "-c", "head -c 1048576 /dev/zero | tr '\\000' A" },
    minimum_bytes = mib,
    reference_input = string.rep("A", mib),
  },
  {
    name = "mixed-ansi-1mib",
    command = { "/bin/sh", "-c", "i=0; while [ $i -lt " .. mixed_repetitions .. " ]; do printf '\\033[31mKiwi\\033[0m\\r\\n'; i=$((i + 1)); done" },
    minimum_bytes = mib,
    reference_input = string.rep(mixed_unit, mixed_repetitions),
  },
  {
    name = "unicode-combining-cjk-emoji-fallback-128kib",
    command = { "/bin/sh", "-c", "i=0; while [ $i -lt " .. unicode_repetitions .. " ]; do printf 'Cafe\\314\\201 \\344\\270\\255 \\360\\237\\221\\251\\342\\200\\215\\360\\237\\232\\200 \\356\\202\\260\\n'; i=$((i + 1)); done" },
    minimum_bytes = #unicode_unit * unicode_repetitions,
    reference_input = string.rep(unicode_pty_unit, unicode_repetitions),
  },
  {
    name = "response-interleaved-128kib",
    command = { "/bin/sh", "-c", "stty -echo -icanon min 1 time 0; printf '\\033[6n'; dd bs=1 count=6 2>/dev/null; stty sane; head -c 131072 /dev/zero | tr '\\000' A" },
    minimum_bytes = 128 * 1024,
    expect_responses = true,
  },
}
if os.getenv("KIWI_BURST_10MB") == "1" then
  cases[#cases + 1] = {
    name = "printable-10mib",
    command = { "/bin/sh", "-c", "head -c 10485760 /dev/zero | tr '\\000' A" },
    minimum_bytes = 10 * mib,
  }
end

local read_budget = number_from_env("KIWI_PTY_READ_BUDGET", 4 * 1024)
local max_service_ms = number_from_env("KIWI_BURST_MAX_SERVICE_MS", 250)
local max_heap_kib = number_from_env("KIWI_BURST_MAX_HEAP_KIB", 64 * 1024)
local results = {}
for _, case in ipairs(cases) do
  local result = run_case(case, read_budget, max_service_ms, max_heap_kib)
  results[#results + 1] = result
  io.stdout:write(string.format(
    "burst %s bytes=%d service=%d active=%d max-service=%.3fms p95=%.3fms elapsed=%.1fms frame-slots=%d response=%d B heap=%.1f KiB rss=%s parser=%d B/%d actions/%d errors\n",
    result.name,
    result.bytes_read,
    result.service_iterations,
    result.active_service_iterations,
    result.max_service_ms,
    result.service_ms.p95,
    result.elapsed_wall_ms,
    result.frame_deadline_slots_serviced_while_output_active,
    result.responses_written,
    result.memory.heap_kib_delta,
    result.memory.rss_kib_delta and string.format("%.1f KiB", result.memory.rss_kib_delta) or "unavailable",
    result.parser.bytes,
    result.parser.actions,
    result.parser.errors
  ))
end

local timestamp = os.date("!%Y%m%dT%H%M%SZ")
local output = "bench/results/" .. timestamp .. "-burst.json"
local file, error_message = io.open(output, "wb")
if not file then
  error("Unable to create " .. output .. ": " .. error_message .. ". Run through make bench-burst so the results directory exists.")
end
local metadata = Environment.collect(timestamp, 1, 0)
metadata.methodology = {
  clock = clock_description,
  scope = "real nonblocking PTY reads, terminal parsing/state updates, terminal-response writes, and bounded live-loop service turns; GPU submission and presentation are excluded",
  memory = "Lua heap retained delta in KiB after an explicit collection; RSS delta is best-effort and unavailable outside Linux /proc",
}
file:write(Json.encode({
  schema_version = 4,
  benchmark = "Kiwi M1.5 real PTY burst service benchmark",
  metadata = metadata,
  configuration = {
    monotonic_clock = clock_description,
    max_heap_kib = max_heap_kib,
    max_service_ms = max_service_ms,
    read_budget_bytes = read_budget,
  },
  results = results,
}), "\n")
file:close()
io.stdout:write("machine-readable result: " .. output .. "\n")
