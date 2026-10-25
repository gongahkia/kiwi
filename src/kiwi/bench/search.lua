-- CPU/model workload, deliberately excludes event-loop sleeps and rendering.
local Terminal = require("kiwi.session.terminal")
local Search = require("kiwi.input.search")
local Metrics = require("kiwi.bench.process_metrics")
local Stats = require("kiwi.bench.stats")
local Json = require("kiwi.bench.json")
local Environment = require("kiwi.bench.environment")
local history = tonumber(arg[1]) or 10000
assert(history >= 1000 and history <= 20000 and history % 1 == 0)
local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = history } })
local state = Terminal.state(terminal)
for line = 1, history + state.rows do
  terminal:write(string.format("%06d %s Café 中\r\n", line, string.rep("a", 40)))
end
assert(state.scrollback:size() == history)
collectgarbage("collect")
local baseline_heap, baseline_rss = collectgarbage("count"), Metrics.resident_kib()
local result = { history_lines = history, columns = 80, rows = 24, step_budget = Search.step_budget,
  baseline_heap_kib = baseline_heap, baseline_resident_kib = baseline_rss, cases = {} }
local cases = {
  { name = "absent_literal", mode = "literal", query = string.rep("a", 60) .. "z", expected = "no-match" },
  { name = "anchored_unicode", mode = "regex", query = string.format("^%06d a{40} Café 中$", math.floor(history / 2)), expected = "matches" },
  { name = "nested_repetition", mode = "regex", query = "((a|aa)+)+z", expected = "no-match" },
  { name = "match_limit", mode = "regex", query = "a", expected = "match-limit" },
}
for _, case in ipairs(cases) do
  state:clear_search(); collectgarbage("collect")
  local heap_before, peak_heap, peak_rss = collectgarbage("count"), collectgarbage("count"), Metrics.resident_kib()
  state:search_begin("forward", case.mode); state:search_append(case.query)
  local cpu, wall, max_work, max_cpu, max_wall = {}, {}, 0, 0, 0
  local total_cpu, total_wall = os.clock(), Metrics.monotonic_seconds()
  local start = true
  repeat
    local before_cpu, before_wall = os.clock(), Metrics.monotonic_seconds()
    if start then state:search_submit(); start = false else state:search_step() end
    cpu[#cpu + 1] = (os.clock() - before_cpu) * 1000
    wall[#wall + 1] = (Metrics.monotonic_seconds() - before_wall) * 1000
    max_work = math.max(max_work, state.search.last_step_work)
    max_cpu, max_wall = math.max(max_cpu, cpu[#cpu]), math.max(max_wall, wall[#wall])
    assert(max_work <= Search.step_budget and state.search.work <= Search.maximum_work)
    peak_heap, peak_rss = math.max(peak_heap, collectgarbage("count")), math.max(peak_rss, Metrics.resident_kib())
  until not state:search_pending()
  local view = state:search_view()
  assert(view.status == case.expected, case.name .. ": " .. view.status)
  if case.expected == "matches" then assert(view.match_count == 1 and view.current.finish_column == 55) end
  assert(peak_heap - heap_before < 16 * 1024, "search temporary heap exceeded 16 MiB")
  result.cases[case.name] = { status = view.status, matches = view.match_count, work = view.work,
    scanned_rows = view.scanned_rows, step_cpu_ms = Stats.summary(cpu), step_wall_ms = Stats.summary(wall),
    max_step_cpu_ms = max_cpu, max_step_wall_ms = max_wall,
    total_cpu_ms = (os.clock() - total_cpu) * 1000, total_wall_ms = (Metrics.monotonic_seconds() - total_wall) * 1000,
    peak_temporary_heap_kib = peak_heap - heap_before, peak_resident_kib = peak_rss, maximum_step_work = max_work }
end
state:search_begin("forward", "regex"); state:search_append("(a+)+z"); state:search_submit()
assert(state:search_pending())
local start = Metrics.monotonic_seconds(); state:clear_search()
result.cancel_ms = (Metrics.monotonic_seconds() - start) * 1000
assert(not state:search_pending())
collectgarbage("collect")
result.retained_heap_kib_delta = collectgarbage("count") - baseline_heap
assert(result.retained_heap_kib_delta < 1024, "search retained more than 1 MiB after cancellation")
result.environment = Environment.collect(os.date("!%Y-%m-%dT%H:%M:%SZ"), 1, 0)
io.stdout:write(Json.encode(result), "\n")
