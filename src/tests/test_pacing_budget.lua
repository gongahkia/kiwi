local Assert = require("tests.assert")
local Json = require("kiwi.bench.json")

local function command_succeeds(command)
  local ok, _, status = os.execute(command)
  return ok == true or ok == 0 or status == 0
end

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function temporary_directory()
  local handle = assert(io.popen("mktemp -d", "r"))
  local directory = assert(handle:read("*l"))
  assert(handle:close())
  return directory
end

local function report(frame_cpu_p95, output_status)
  return {
    engine = "Kiwi frame pacing methodology",
    metadata = {
      configuration = { present_mode = "fifo", pty_read_budget = 4096, sample_limit = 2, warmup_frames = 1 },
      methodology = { clock = "GLFW monotonic time", samples = "bounded aggregate summaries", scope = "native frame return" },
      runtime = { luajit = "fixture" },
      system = { architecture = "fixture", display_session = "fixture", kernel = "fixture" },
    },
    measurement = {
      frame_cpu_ms = { p95 = frame_cpu_p95, status = "measured" },
      frame_interval_ms = { p95 = 10, status = "measured" },
      output_to_present_ms = output_status == "measured"
        and { p95 = 5, status = "measured" }
        or { count = 0, status = "unavailable" },
    },
    methodology = { privacy = "aggregate only" },
    schema_version = 1,
  }
end

local function write(path, value)
  local file = assert(io.open(path, "wb"))
  file:write(Json.encode(value), "\n")
  file:close()
end

return {
  pacing_budget_requires_a_same_environment_comparable_p95 = function()
    if not command_succeeds("command -v jq >/dev/null 2>&1") then return end
    local root = os.getenv("KIWI_ROOT") or "."
    local directory = temporary_directory()
    local baseline = directory .. "/baseline.json"
    local candidate = directory .. "/candidate.json"
    write(baseline, report(2, "unavailable"))
    write(candidate, report(2.4, "unavailable"))
    local compare = shell_quote(root .. "/script/compare-pacing") .. " " .. shell_quote(baseline) .. " " .. shell_quote(candidate)
    local budget = shell_quote(root .. "/script/check-pacing-budget") .. " " .. shell_quote(baseline) .. " " .. shell_quote(candidate)
    Assert.truthy(command_succeeds(compare))
    Assert.truthy(command_succeeds(budget))

    write(candidate, report(2.6, "unavailable"))
    Assert.truthy(not command_succeeds(budget .. " >/dev/null 2>&1"))

    write(candidate, report(2.4, "measured"))
    Assert.truthy(not command_succeeds(budget .. " >/dev/null 2>&1"))
    os.remove(baseline)
    os.remove(candidate)
    Assert.truthy(command_succeeds("rmdir " .. shell_quote(directory)))
  end,
}
