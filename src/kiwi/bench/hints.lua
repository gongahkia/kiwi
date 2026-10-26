-- CPU/model workload; excludes rendering, opener/clipboard latency and sleeps.
local Terminal = require("kiwi.session.terminal")
local Hints = require("kiwi.input.hints")
local Metrics = require("kiwi.bench.process_metrics")
local Stats = require("kiwi.bench.stats")
local Json = require("kiwi.bench.json")
local Environment = require("kiwi.bench.environment")
local history = tonumber(arg[1]) or 10000
assert(history >= 1000 and history <= 20000 and history % 1 == 0)
local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = history } })
for index = 1, history + 24 do terminal:write(string.format("history %06d\r\n", index)) end
terminal:write("https://visible.example/path")
local state = Terminal.state(terminal)
assert(state.scrollback:size() == history)
collectgarbage("collect")
local result = { history_lines = history, step_budget = Hints.step_budget, maximum_work = Hints.maximum_work,
  baseline_heap_kib = collectgarbage("count"), baseline_resident_kib = Metrics.resident_kib(), cases = {} }
local function run(name, model, expected, count)
  collectgarbage("collect")
  local before_heap, peak_heap = collectgarbage("count"), collectgarbage("count")
  local cpu, wall, work, maximum, max_cpu, first = {}, {}, 0, 0, 0, true
  local total_cpu, total_wall = os.clock(), Metrics.monotonic_seconds()
  repeat
    local before_cpu, before_wall = os.clock(), Metrics.monotonic_seconds()
    if first then model:hints_begin(); first = false else model:hints_step() end
    cpu[#cpu + 1] = (os.clock() - before_cpu) * 1000
    wall[#wall + 1] = (Metrics.monotonic_seconds() - before_wall) * 1000
    work, maximum = work + model.hints.last_step_work, math.max(maximum, model.hints.last_step_work)
    max_cpu, peak_heap = math.max(max_cpu, cpu[#cpu]), math.max(peak_heap, collectgarbage("count"))
    assert(maximum <= Hints.step_budget and work <= Hints.maximum_work)
  until not model:hints_pending()
  local view = model:hints_view()
  assert(view.status == expected and (not count or view.count == count), name .. ": " .. view.status .. "/" .. view.count)
  assert(peak_heap - before_heap < 8 * 1024, "hint temporary heap exceeded 8 MiB")
  result.cases[name] = { status = view.status, count = view.count, pages = view.pages,
    work = work, maximum_step_work = maximum, max_step_cpu_ms = max_cpu,
    step_cpu_ms = Stats.summary(cpu), step_wall_ms = Stats.summary(wall),
    total_cpu_ms = (os.clock() - total_cpu) * 1000, total_wall_ms = (Metrics.monotonic_seconds() - total_wall) * 1000,
    peak_temporary_heap_kib = peak_heap - before_heap }
  model.hints:clear(); collectgarbage("collect")
  result.cases[name].retained_heap_kib_delta = collectgarbage("count") - before_heap
  assert(result.cases[name].retained_heap_kib_delta < 1024)
end
run("visible_after_large_history", state, "ready", 1)
-- Scanning a viewport must not enumerate the complete retained history.
assert(result.cases.visible_after_large_history.work < 5000)
local function links(number, length)
  local parts = {}
  for index = 1, number do
    parts[index] = "\27]8;;https://e.example/" .. index .. "/" .. string.rep("x", length) .. "\27\\x\27]8;;\27\\"
  end
  local target = Terminal.new({ columns = 100, rows = 4 })
  target:write(table.concat(parts))
  return Terminal.state(target)
end
run("dense_long_targets", links(64, 1900), "ready", 64)
run("match_limit", links(300, 0), "match-limit", Hints.maximum_matches)
run("validation_work_limit", links(150, 2000), "scan-limit")
local pending = links(64, 1900)
pending:hints_begin(); assert(pending:hints_pending() and #pending.hints:labels(pending) == 0)
local before = Metrics.monotonic_seconds(); pending.hints:clear()
result.cancel_ms = (Metrics.monotonic_seconds() - before) * 1000
assert(not pending:hints_pending() and not pending.hints.active)
result.environment = Environment.collect(os.date("!%Y-%m-%dT%H:%M:%SZ"), 1, 0)
io.stdout:write(Json.encode(result), "\n")
