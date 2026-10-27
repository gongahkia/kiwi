local ffi = require("ffi")
local Environment = require("kiwi.bench.environment")
local Json = require("kiwi.bench.json")
local Parser = require("kiwi.terminal.parser")
local Pty = require("kiwi.process.pty")
local OutputService = require("kiwi.process.output_service")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")
local Stats = require("kiwi.bench.stats")
local Utf8 = require("kiwi.terminal.utf8")
local Burst = {}

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

local resident_kib = require("kiwi.bench.process_metrics").resident_kib

local function expected_snapshot(input)
  local state = State.new(80, 24, { scrollback_limit = 256 })
  state.damage:clear()
  local parser = Parser.new(state)
  parser:feed(input)
  parser:finish()
  return Snapshot.encode(state)
end

function Burst.run_case(case, read_budget, max_service_ms, max_heap_kib)
  local timeout = case.timeout_seconds or 90
  assert(timeout > 0 and timeout <= 90, "burst timeout must be positive and at most 90 seconds")
  local expected = case.reference_input and expected_snapshot(case.reference_input) or nil
  collectgarbage("collect")
  local heap_before = collectgarbage("count")
  local rss_before = resident_kib()
  local state = State.new(80, 24, { scrollback_limit = 256 })
  state.damage:clear()
  local parser = Parser.new(state)
  local bytes = 0
  local service_iterations = 0
  local active_service_iterations = 0
  local max_service = 0
  local service_samples = {}
  local frame_deadline_slots = 0
  local status
  local output_service = OutputService.new({ max_bytes = read_budget, clock = monotonic_seconds })
  local pty = Pty.spawn(case.command, 80, 24, { TERM = "xterm-kiwi", COLORTERM = "truecolor" })
  local started = monotonic_seconds()
  local next_frame_deadline = started
  local deadline = started + timeout
  local sessions = { { pty = pty } }
  local function consume(_, output)
    bytes = bytes + #output
    parser:feed(output)
  end

  local ok, message = xpcall(function()
    while true do
      local service_started = monotonic_seconds()
      pty:flush()
      local output_bytes = output_service:drain(sessions, consume)
      assert(output_bytes <= read_budget, "PTY service exceeded its configured budget")
      if output_bytes > 0 then active_service_iterations = active_service_iterations + 1 end
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
      if output_bytes > 0 then
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
  end, debug.traceback)
  local cleanup_ok, cleanup_message = pcall(pty.shutdown, pty)
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
    service_ms = #service_samples > 0 and Stats.summary(service_samples) or { count = 0 },
    elapsed_wall_ms = elapsed_ms,
    frame_deadline_slots_serviced_while_output_active = frame_deadline_slots,
    child_pid = pty.pid,
    child_status = pty.exit_status,
    pty_closed = pty.fd == nil,
    parser = parser.stats,
    responses_written = pty.bytes_written,
    memory = {
      heap_kib_delta = heap_after - heap_before,
      rss_kib_delta = rss_before and rss_after and rss_after - rss_before or nil,
    },
  }
  local snapshot_ok, snapshot = pcall(Snapshot.encode, state)
  if snapshot_ok then result.final_snapshot = snapshot else result.snapshot_failure = tostring(snapshot):sub(1, 4096) end
  if not cleanup_ok then result.cleanup_failure = tostring(cleanup_message):sub(1, 4096) end
  local checks_ok, checks_message = xpcall(function()
    assert(ok, message)
    assert(cleanup_ok, cleanup_message)
    assert(snapshot_ok, snapshot)
    assert(status and status.kind == "exit" and status.code == 0, case.name .. " child did not exit successfully")
    assert(bytes >= case.minimum_bytes, case.name .. " output was truncated")
    assert(max_service <= max_service_ms, string.format("%s service turn %.3fms exceeded %.3fms", case.name, max_service, max_service_ms))
    assert(result.memory.heap_kib_delta <= max_heap_kib, string.format("%s retained Lua heap %.1f KiB exceeded %d KiB", case.name, result.memory.heap_kib_delta, max_heap_kib))
    if expected then assert(result.final_snapshot == expected, case.name .. " final canonical snapshot diverged") end
    if case.expect_responses then assert(result.responses_written > 0, case.name .. " terminal response was starved") end
  end, debug.traceback)
  result.status = checks_ok and "passed" or "failed"
  if not checks_ok then result.failure = tostring(checks_message):sub(1, 4096) end
  return result
end

local function default_cases()
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
  return cases
end

local function write_report(output, report)
  local encoded = Json.encode(report)
  assert(#encoded <= 8 * 1024 * 1024, "burst report exceeded 8 MiB")
  local temporary = output .. ".new"
  local file = assert(io.open(temporary, "wb"))
  local ok, message = file:write(encoded, "\n")
  local closed, close_message = file:close()
  assert(ok, message); assert(closed, close_message)
  assert(os.rename(temporary, output))
end

function Burst.main(options)
  options = options or {}
  local read_budget = options.read_budget or number_from_env("KIWI_PTY_READ_BUDGET", OutputService.default_max_bytes)
  local max_service_ms = options.max_service_ms or number_from_env("KIWI_BURST_MAX_SERVICE_MS", 250)
  local max_heap_kib = options.max_heap_kib or number_from_env("KIWI_BURST_MAX_HEAP_KIB", 64 * 1024)
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local output = options.report_path or os.getenv("KIWI_BURST_REPORT") or "bench/results/" .. timestamp .. "-burst.json"
  local metadata = Environment.collect(timestamp, 1, 0)
  metadata.methodology = {
    clock = clock_description,
    scope = "real nonblocking PTY reads, terminal parsing/state updates, terminal-response writes, and bounded live-loop service turns; GPU submission and presentation are excluded",
    memory = "Lua heap retained delta in KiB after an explicit collection; RSS delta is best-effort and unavailable outside Linux /proc",
  }
  local report = {
    schema_version = 4,
    status = "running",
    benchmark = "Kiwi M1.5 real PTY burst service benchmark",
    metadata = metadata,
    configuration = {
      monotonic_clock = clock_description,
      max_heap_kib = max_heap_kib,
      max_service_ms = max_service_ms,
      read_budget_bytes = read_budget,
      read_chunk_bytes = OutputService.chunk_bytes,
      output_service_target_seconds = OutputService.max_seconds,
    },
    results = {},
  }
  write_report(output, report)
  for _, case in ipairs(options.cases or default_cases()) do
    local ok, result = xpcall(function() return Burst.run_case(case, read_budget, max_service_ms, max_heap_kib) end, debug.traceback)
    if not ok then result = { name = case.name, status = "failed", failure = tostring(result):sub(1, 4096) } end
    report.results[#report.results + 1] = result
    if result.status == "failed" then report.status, report.failure = "failed", result.failure end
    write_report(output, report)
    if result.bytes_read then
      io.stdout:write(string.format("burst %s status=%s bytes=%d max-service=%.3fms p95=%s heap=%.1f KiB\n",
        result.name, result.status, result.bytes_read, result.max_service_ms,
        result.service_ms.p95 and string.format("%.3fms", result.service_ms.p95) or "unavailable", result.memory.heap_kib_delta))
    end
    if report.status == "failed" then break end
  end
  if report.status ~= "failed" then report.status = "complete" end
  write_report(output, report)
  io.stdout:write("machine-readable result: " .. output .. "\n")
  return report
end

if ... == nil then
  local report = Burst.main()
  assert(report.status == "complete", report.failure)
end
return Burst
