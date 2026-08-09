local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local Stats = require("kiwi.bench.stats")

local ParserBench = {}

local function repeated(value, count)
  local values = {}
  for index = 1, count do
    values[index] = value
  end
  return table.concat(values)
end

function ParserBench.workloads()
  return {
    {
      name = "printable-ascii",
      input = repeated("Kiwi terminal parser benchmark: printable ASCII output.\r\n", 96),
    },
    {
      name = "sgr-heavy",
      input = repeated("\27[1;31mred\27[0m \27[38;5;196mindexed\27[0m \27[38;2;1;2;3mrgb\27[0m\r\n", 96),
    },
    {
      name = "cursor-erase-tui",
      input = repeated("\27[2J\27[Hstatus\27[10G42%\27[2;1H\27[Kprogress\27[3;5H\27[4P\27[2@ok", 96),
    },
    {
      name = "scrolling-newlines",
      input = repeated("line 000000000000000000000000000000000000000000000000000000000000000000000000\r\n", 192),
    },
    {
      name = "mixed-captured-style",
      input = repeated("\27]2;Kiwi bench\7\27[?1049h\27[H\27[1;34mKiwi\27[0m €\r\n\27[2;1H\27[K\27[?25l\27[?2004h\27[6n\27[?1049l", 96),
    },
  }
end

function ParserBench.run_workload(workload, iterations)
  local samples = {}
  local bytes = 0
  local actions = 0
  local dirty_cells = 0
  local dirty_ranges = 0
  local heap_before = collectgarbage("count")
  for iteration = 1, iterations do
    local state = State.new(80, 24, { scrollback_limit = 256 })
    state.damage:clear()
    local parser = Parser.new(function(action)
      state:apply(action)
    end)
    local started = os.clock()
    parser:feed(workload.input)
    parser:finish()
    samples[iteration] = (os.clock() - started) * 1000
    bytes = bytes + parser.stats.bytes
    actions = actions + parser.stats.actions
    dirty_cells = dirty_cells + state.damage.dirty_count
    dirty_ranges = dirty_ranges + #state.damage:ranges()
  end
  local elapsed_ms = Stats.summary(samples)
  local elapsed_seconds = elapsed_ms.mean * iterations / 1000
  return {
    workload = workload.name,
    iterations = iterations,
    bytes = bytes,
    actions = actions,
    dirty_cells = dirty_cells,
    dirty_ranges = dirty_ranges,
    heap_kib_delta = collectgarbage("count") - heap_before,
    throughput_bytes_per_second = elapsed_seconds > 0 and bytes / elapsed_seconds or 0,
    cpu_parse_state_ms = elapsed_ms,
  }
end

function ParserBench.run(iterations)
  local results = {}
  for _, workload in ipairs(ParserBench.workloads()) do
    results[#results + 1] = ParserBench.run_workload(workload, iterations)
  end
  return results
end

return ParserBench
