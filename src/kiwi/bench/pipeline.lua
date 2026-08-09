local ffi = require("ffi")
local Damage = require("kiwi.terminal.damage")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")
local ParserBench = require("kiwi.bench.parser")
local Renderer = require("kiwi.renderer.renderer")
local Stats = require("kiwi.bench.stats")

local Pipeline = {}

local function measure(iterations, warmup, setup, operation, inspect)
  for _ = 1, warmup do
    local context = setup()
    operation(context)
    if inspect then inspect(context, false) end
  end

  collectgarbage("collect")
  local heap_before = collectgarbage("count")
  local heap_peak = heap_before
  local samples = {}
  for iteration = 1, iterations do
    local context = setup()
    local started = os.clock()
    operation(context)
    samples[iteration] = (os.clock() - started) * 1000
    if inspect then inspect(context, true) end
    heap_peak = math.max(heap_peak, collectgarbage("count"))
  end
  collectgarbage("collect")
  local heap_after = collectgarbage("count")
  return Stats.summary(samples), {
    peak_kib_delta = heap_peak - heap_before,
    retained_kib_delta = heap_after - heap_before,
  }
end

local function result(component, workload, iterations, warmup, input_bytes, timing, memory, totals, scope)
  local elapsed_seconds = timing.total / 1000
  return {
    component = component,
    workload = workload,
    scope = scope,
    iterations = iterations,
    warmup_iterations = warmup,
    input_bytes_per_iteration = input_bytes,
    bytes = input_bytes * iterations,
    actions = totals.actions or 0,
    dirty_cells = totals.dirty_cells or 0,
    dirty_ranges = totals.dirty_ranges or 0,
    cells_packed = totals.cells_packed or 0,
    bytes_packed = totals.bytes_packed or 0,
    scrollback_lines = totals.scrollback_lines or 0,
    throughput_bytes_per_second = elapsed_seconds > 0 and (input_bytes * iterations) / elapsed_seconds or 0,
    cpu_ms = timing,
    memory = memory,
  }
end

local function collect_actions(input)
  local actions = {}
  local parser = Parser.new(function(action)
    actions[#actions + 1] = action
  end)
  parser:feed(input)
  parser:finish()
  return actions
end

local function parser_only(workload, iterations, warmup)
  local totals = { bytes = #workload.input, actions = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local context = { actions = 0 }
    context.parser = Parser.new(function(action)
      if action.kind then
        context.actions = context.actions + 1
      end
    end)
    return context
  end, function(context)
    context.parser:feed(workload.input)
    context.parser:finish()
  end, function(context, recorded)
    if recorded then
      assert(context.actions == context.parser.stats.actions, "parser callback did not observe every action")
      totals.actions = totals.actions + context.parser.stats.actions
    end
  end)
  return result("parser-only-action-materialization", workload.name, iterations, warmup, #workload.input, timing, memory, totals, "parser byte stream through action-table construction and callback; terminal state excluded")
end

local function state_only(workload, iterations, warmup)
  local actions = collect_actions(workload.input)
  local totals = { bytes = #workload.input, actions = #actions * iterations, dirty_cells = 0, dirty_ranges = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local state = State.new(80, 24, { scrollback_limit = 256 })
    state.damage:clear()
    return { state = state }
  end, function(context)
    for _, action in ipairs(actions) do
      context.state:apply(action)
    end
  end, function(context, recorded)
    if recorded then
      totals.dirty_cells = totals.dirty_cells + context.state.damage.dirty_count
      totals.dirty_ranges = totals.dirty_ranges + #context.state.damage:ranges()
    end
  end)
  return result("state-only-action-application", workload.name, iterations, warmup, #workload.input, timing, memory, totals, "pre-materialized parser actions through terminal state and damage; parser excluded")
end

local function parser_state(workload, iterations, warmup)
  local totals = { bytes = #workload.input, actions = 0, dirty_cells = 0, dirty_ranges = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local state = State.new(80, 24, { scrollback_limit = 256 })
    state.damage:clear()
    return { state = state, parser = Parser.new(state) }
  end, function(context)
    context.parser:feed(workload.input)
    context.parser:finish()
  end, function(context, recorded)
    if recorded then
      totals.actions = totals.actions + context.parser.stats.actions
      totals.dirty_cells = totals.dirty_cells + context.state.damage.dirty_count
      totals.dirty_ranges = totals.dirty_ranges + #context.state.damage:ranges()
    end
  end)
  return result("parser-state", workload.name, iterations, warmup, #workload.input, timing, memory, totals, "streaming parser plus terminal state using the production direct print sink; renderer packing excluded")
end

local function utf8_scan(name, input, iterations, warmup)
  local totals = { bytes = #input, actions = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local context = { codepoints = 0 }
    context.decoder = Utf8.Decoder.new(function()
      context.codepoints = context.codepoints + 1
    end)
    return context
  end, function(context)
    for index = 1, #input do
      context.decoder:feed_byte(input:byte(index))
    end
    context.decoder:finish()
  end, function(context, recorded)
    if recorded then totals.actions = totals.actions + context.codepoints end
  end)
  return result("byte-utf8-scanning", name, iterations, warmup, #input, timing, memory, totals, "byte iteration and UTF-8 decoding callback; parser and terminal state excluded")
end

local function damage_result(name, count, stride, iterations, warmup)
  local totals = { bytes = 0, actions = 0, cells_packed = 0, dirty_cells = 0, dirty_ranges = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { damage = Damage.new(count) }
  end, function(context)
    for index = 0, count - 1, stride do
      context.damage:mark(index)
    end
    context.range_count = #context.damage:ranges()
    context.dirty_count = context.damage.dirty_count
    context.damage:clear()
  end, function(context, recorded)
    if recorded then
      totals.dirty_cells = totals.dirty_cells + context.dirty_count
      totals.dirty_ranges = totals.dirty_ranges + context.range_count
    end
  end)
  return result("damage-coalescing", name, iterations, warmup, 0, timing, memory, totals, "Damage mark, range discovery, and clear only; terminal state and packing excluded")
end

local function new_packer(cell_count)
  local glyph = { u0 = 0, v0 = 0, u1 = 1, v1 = 1 }
  return {
    cells = ffi.new("KiwiGlyphInstance[?]", cell_count),
    font = {
      atlas = {
        get = function(_, text)
          return text == " " and nil or glyph
        end,
      },
    },
  }
end

local function packing_result(columns, rows, iterations, warmup)
  local cell_count = columns * rows
  local input = string.rep("Kiwi 123 € ", math.ceil(cell_count / 11))
  local totals = { bytes = #input, cells_packed = cell_count * iterations, bytes_packed = cell_count * 40 * iterations }
  local timing, memory = measure(iterations, warmup, function()
    local state = State.new(columns, rows, { scrollback_limit = 64 })
    local parser = Parser.new(state)
    parser:feed(input)
    parser:finish()
    return { state = state, packer = new_packer(cell_count) }
  end, function(context)
    for index = 0, cell_count - 1 do
      Renderer.pack_cell(context.packer, context.state, index)
    end
  end)
  return result("renderer-cpu-packing", string.format("%dx%d", columns, rows), iterations, warmup, #input, timing, memory, totals, "Renderer:pack_cell over every visible cell with a deterministic atlas stub; GPU queue write and presentation excluded")
end

local function scroll_result(name, columns, rows, margins, iterations, warmup)
  local totals = { bytes = 0, actions = 0, dirty_cells = 0, dirty_ranges = 0, scrollback_lines = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local state = State.new(columns, rows, { scrollback_limit = 128 })
    state.damage:clear()
    if margins then state:set_margins(margins[1], margins[2]) end
    return { state = state }
  end, function(context)
    context.state:scroll_up(1)
    context.dirty_cells = context.state.damage.dirty_count
    context.dirty_ranges = #context.state.damage:ranges()
    context.state.damage:clear()
  end, function(context, recorded)
    if recorded then
      totals.dirty_cells = totals.dirty_cells + context.dirty_cells
      totals.dirty_ranges = totals.dirty_ranges + context.dirty_ranges
      totals.scrollback_lines = totals.scrollback_lines + context.state.scrollback:size()
    end
  end)
  return result("real-terminal-scroll", name, iterations, warmup, 0, timing, memory, totals, "State:scroll_up on row-reference screens, bounded scrollback, damage range discovery, and clear; parser and renderer excluded")
end

local function full_pipeline(workload, iterations, warmup)
  local cell_count = 80 * 24
  local totals = { bytes = #workload.input, actions = 0, dirty_cells = 0, dirty_ranges = 0, cells_packed = 0, bytes_packed = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local state = State.new(80, 24, { scrollback_limit = 256 })
    state.damage:clear()
    return { state = state, parser = Parser.new(state), packer = new_packer(cell_count) }
  end, function(context)
    context.parser:feed(workload.input)
    context.parser:finish()
    local ranges = context.state.damage:ranges()
    local packed = 0
    for _, range in ipairs(ranges) do
      for index = range.first, range.first + range.count - 1 do
        Renderer.pack_cell(context.packer, context.state, index)
      end
      packed = packed + range.count
    end
    context.packed = packed
    context.dirty_cells = context.state.damage.dirty_count
    context.dirty_ranges = #ranges
    context.state.damage:clear()
  end, function(context, recorded)
    if recorded then
      totals.actions = totals.actions + context.parser.stats.actions
      totals.dirty_cells = totals.dirty_cells + context.dirty_cells
      totals.dirty_ranges = totals.dirty_ranges + context.dirty_ranges
      totals.cells_packed = totals.cells_packed + context.packed
      totals.bytes_packed = totals.bytes_packed + context.packed * 40
    end
  end)
  return result("full-cpu-pipeline", workload.name, iterations, warmup, #workload.input, timing, memory, totals, "PTY bytes are represented by an in-memory stream through parser, state, damage range discovery, and Renderer:pack_cell; PTY syscalls, GPU queue writes, GPU execution, and presentation excluded")
end

function Pipeline.run(iterations, warmup)
  local workloads = ParserBench.workloads()
  local results = {
    byte_utf8 = {
      utf8_scan("ascii-printable", string.rep("Kiwi terminal UTF-8 scanner.\r\n", 128), iterations, warmup),
      utf8_scan("multibyte-valid", string.rep("Kiwi € terminal 漢字.\r\n", 128), iterations, warmup),
      utf8_scan("invalid-sequences", string.rep("Kiwi\255\128 terminal\r\n", 128), iterations, warmup),
    },
    parser_only = {},
    state_only = {},
    parser_state = {},
    damage = {
      damage_result("contiguous-80x24", 80 * 24, 1, iterations, warmup),
      damage_result("fragmented-80x24-stride-3", 80 * 24, 3, iterations, warmup),
    },
    packing = {
      packing_result(80, 24, iterations, warmup),
      packing_result(160, 50, iterations, warmup),
    },
    scroll = {
      scroll_result("primary-full-80x24", 80, 24, nil, iterations, warmup),
      scroll_result("primary-full-240x80", 240, 80, nil, iterations, warmup),
      scroll_result("margin-2-23-80x24", 80, 24, { 2, 23 }, iterations, warmup),
    },
    full_cpu_pipeline = {},
  }
  for _, workload in ipairs(workloads) do
    results.parser_only[#results.parser_only + 1] = parser_only(workload, iterations, warmup)
    results.state_only[#results.state_only + 1] = state_only(workload, iterations, warmup)
    results.parser_state[#results.parser_state + 1] = parser_state(workload, iterations, warmup)
    results.full_cpu_pipeline[#results.full_cpu_pipeline + 1] = full_pipeline(workload, iterations, warmup)
  end
  return results
end

function Pipeline.print_results(results)
  local order = { "byte_utf8", "parser_only", "state_only", "parser_state", "damage", "packing", "scroll", "full_cpu_pipeline" }
  for _, layer in ipairs(order) do
    for _, item in ipairs(results[layer]) do
      io.stdout:write(string.format(
        "m1.5 %-35s %-28s iterations=%d warmup=%d cpu mean=%.4fms p50=%.4fms p95=%.4fms p99=%.4fms throughput=%.0f B/s dirty=%d/%d packed=%d heap retained=%.1f KiB peak=%.1f KiB\n",
        item.component,
        item.workload,
        item.iterations,
        item.warmup_iterations,
        item.cpu_ms.mean,
        item.cpu_ms.p50,
        item.cpu_ms.p95,
        item.cpu_ms.p99,
        item.throughput_bytes_per_second,
        item.dirty_cells,
        item.dirty_ranges,
        item.cells_packed,
        item.memory.retained_kib_delta,
        item.memory.peak_kib_delta
      ))
    end
  end
end

return Pipeline
