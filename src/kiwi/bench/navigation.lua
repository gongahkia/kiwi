-- CPU/model qualification only; does not measure GPU/input presentation latency.
local Terminal = require("kiwi.session.terminal")
local Vi = require("kiwi.input.vi")
local Metrics = require("kiwi.bench.process_metrics")
local Stats = require("kiwi.bench.stats")
local Json = require("kiwi.bench.json")
local Environment = require("kiwi.bench.environment")
local history = tonumber(arg[1]) or 10000
assert(history >= 1000 and history <= 20000 and history % 1 == 0)
local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = history } })
local state = Terminal.state(terminal)
-- One very long logical line stresses wrap traversal and semantic selection.
for _ = 1, history + state.rows do terminal:write(string.rep("a", state.columns)) end
assert(state.scrollback:size() == history)
state:vi_toggle(); state.vi:motion(state, "top"); state.vi:motion(state, "first")
collectgarbage("collect")
local baseline = collectgarbage("count")
local result = { history_lines = history, columns = state.columns, rows = state.rows,
  step_budget = Vi.step_budget, maximum_work = Vi.maximum_work,
  baseline_heap_kib = baseline, baseline_resident_kib = Metrics.resident_kib(), cases = {} }
local function run(name, begin, verify)
  state.vi:cancel(state); state.vi:motion(state, "top"); state.vi:motion(state, "first")
  collectgarbage("collect")
  local heap, peak, peak_rss = collectgarbage("count"), collectgarbage("count"), Metrics.resident_kib()
  local cpu, wall, work, maximum, first = {}, {}, 0, 0, true
  local total_cpu, total_wall = os.clock(), Metrics.monotonic_seconds()
  repeat
    local before_cpu, before_wall = os.clock(), Metrics.monotonic_seconds()
    if first then begin(); first = false else state:vi_step() end
    cpu[#cpu + 1] = (os.clock() - before_cpu) * 1000
    wall[#wall + 1] = (Metrics.monotonic_seconds() - before_wall) * 1000
    local used = state.vi.last_step_work or 0
    work, maximum = work + used, math.max(maximum, used)
    assert(used <= Vi.step_budget and work <= Vi.maximum_work)
    peak, peak_rss = math.max(peak, collectgarbage("count")), math.max(peak_rss, Metrics.resident_kib())
  until not state:vi_pending()
  local elapsed_cpu, elapsed_wall = (os.clock() - total_cpu) * 1000, (Metrics.monotonic_seconds() - total_wall) * 1000
  verify()
  assert(peak - heap < 16 * 1024, "navigation temporary heap exceeded 16 MiB")
  result.cases[name] = { step_cpu_ms = Stats.summary(cpu), step_wall_ms = Stats.summary(wall),
    total_cpu_ms = elapsed_cpu, total_wall_ms = elapsed_wall, maximum_step_work = maximum, work = work,
    peak_temporary_heap_kib = peak - heap, peak_resident_kib = peak_rss, status = state.vi.status }
end
run("word_end", function() state.vi:motion(state, "word-end") end, function()
  assert(state.vi.cursor.row_index == state:document():count() and state.vi.cursor.column == state.columns - 1)
end)
run("line_selection", function() state.vi:toggle_selection(state, "line") end, function()
  local view = state:selection_view()
  assert(view.start.row_index == 1 and view.finish.row_index == state:document():count())
end)
run("word_selection", function() state.vi:toggle_selection(state, "word") end, function()
  assert(#state:selection_text(2 * 1024 * 1024) == state.columns * state:document():count())
end)
state.vi:cancel(state); state.vi:motion(state, "top"); state.vi:motion(state, "first")
state.vi:toggle_selection(state, "word"); assert(state:vi_pending())
local started = Metrics.monotonic_seconds(); state.vi:cancel(state)
result.cancel_ms = (Metrics.monotonic_seconds() - started) * 1000
assert(not state:vi_pending() and not state:selection_view().active)
collectgarbage("collect")
result.retained_heap_kib_delta = collectgarbage("count") - baseline
assert(result.retained_heap_kib_delta < 1024, "navigation retained heap KiB: " .. result.retained_heap_kib_delta)
result.environment = Environment.collect(os.date("!%Y-%m-%dT%H:%M:%SZ"), 1, 0)
io.stdout:write(Json.encode(result), "\n")
