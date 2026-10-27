local Terminal = require('kiwi.session.terminal')
local Json = require('kiwi.bench.json')
local line = '\27[1;38;2;90;180;230m背景 café é Ελληνικά\27[0m \27[3m日本語\27[0m \27[4:3munderlined\27[0m\r\n\27[1;72HACK0001  \27[24;1H'
local warmup = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = 64 } })
for _ = 1, 300 do warmup:write(line) end
warmup:close(); warmup = nil
collectgarbage('collect')
local baseline = collectgarbage('count')
local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = 10000 } })
terminal:write('\27[24;1H')
local peak, started = baseline, os.clock()
for index = 1, 20000 do
  terminal:write(line)
  if index % 100 == 0 then peak = math.max(peak, collectgarbage('count')) end
end
local elapsed = os.clock() - started
collectgarbage('collect')
local state = Terminal.state(terminal)
assert(state.scrollback:size() == 10000)
print(Json.encode({ history_rows = state.scrollback:size(), written_lines = 20000, columns = 80,
  retained_heap_kib = collectgarbage('count') - baseline, sampled_peak_heap_kib = peak - baseline, cpu_seconds = elapsed }))
terminal:close()
