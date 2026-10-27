local Assert = require("tests.assert")
local Service = require("kiwi.process.output_service")
local Terminal = require("kiwi.session.terminal")
local Snapshot = require("kiwi.terminal.snapshot")

local function session(bytes)
  return { pty = { bytes = bytes, reads = {}, read_available = function(self, limit)
    self.reads[#self.reads + 1] = limit
    local output = self.bytes:sub(1, limit)
    self.bytes = self.bytes:sub(#output + 1)
    return output
  end }, output = "" }
end

local function consume(target, output) target.output = target.output .. output end

return {
  output_service_batches_fast_reads_within_both_byte_bounds = function()
    local target = session(string.rep("x", 20000))
    local service = Service.new({ clock = function() return 0 end })
    local bytes, calls = service:drain({ target }, consume)
    Assert.equal(bytes, Service.default_max_bytes)
    Assert.equal(calls, 4)
    Assert.equal(#target.output, bytes)
    for _, requested in ipairs(target.pty.reads) do Assert.truthy(requested <= Service.chunk_bytes) end
    Assert.truthy(service.pending)
    service:drain({ target }, consume)
    Assert.equal(target.output, string.rep("x", 20000))
    Assert.equal(service.pending, false)
  end,
  output_service_yields_after_expensive_parsing_and_rotates_panes = function()
    local now = 0
    local service = Service.new({ clock = function() return now end })
    local a, b, c = session(string.rep("a", 20000)), session(string.rep("b", 20000)), session(string.rep("c", 20000))
    local visited = {}
    local function slow(target, output)
      visited[#visited + 1] = target
      consume(target, output)
      now = now + 0.020 -- One non-preemptible parse already exceeds the target.
    end
    local _, calls = service:drain({ a, b, c }, slow)
    Assert.equal(calls, 1)
    Assert.truthy(service.pending)
    service:drain({ c, a, b }, slow) -- The deferred pane moved in the array.
    Assert.equal(visited[1], a)
    Assert.equal(visited[2], b)
    service:drain({ a, b }, slow) -- Closing the deferred pane cannot leave a stale cursor.
    Assert.equal(visited[3], a)
    service:drain({ a, b }, slow)
    Assert.equal(visited[4], b)
  end,
  output_service_small_global_budget_cannot_starve_a_later_pane = function()
    local service = Service.new({ max_bytes = 1, clock = function() return 0 end })
    local a, b, c = session("AA"), session("BB"), session("CC")
    for _ = 1, 6 do Assert.equal(service:drain({ a, b, c }, consume), 1) end
    Assert.equal(a.output, "AA"); Assert.equal(b.output, "BB"); Assert.equal(c.output, "CC")
    local bytes, calls = service:drain({ a, b, c }, consume)
    Assert.equal(bytes, 0); Assert.equal(calls, 3); Assert.equal(service.pending, false)
    service:drain({}, consume)
    Assert.equal(service.next_pty, nil)
  end,
  output_service_empty_and_short_reads_do_not_spin_until_the_deadline = function()
    local service = Service.new({ clock = function() return 0 end })
    local a, b, c = session(""), session("short"), session("")
    local bytes, calls = service:drain({ a, b, c }, consume)
    Assert.equal(bytes, 5); Assert.equal(calls, 3); Assert.equal(service.pending, false)
    Assert.equal(b.output, "short")
  end,
  output_service_preserves_independent_unicode_and_protocol_streams = function()
    local streams = {
      string.rep("\27[31m界é\27[0m\r\n", 40),
      string.rep("\27]8;;https://example.com\7👩‍🚀\27]8;;\7\r\n", 40),
    }
    local now = 0
    local service = Service.new({ max_bytes = 13, clock = function() return now end })
    local sessions = {}
    for _, bytes in ipairs(streams) do
      local target = session(bytes)
      target.terminal = Terminal.new({ columns = 20, rows = 3 })
      sessions[#sessions + 1] = target
    end
    for _ = 1, 2000 do
      service:drain(sessions, function(target, output)
        target.terminal:write(output)
        now = now + 0.005
      end)
      if not service.pending then break end
    end
    Assert.equal(service.pending, false)
    for index, target in ipairs(sessions) do
      Assert.equal(target.pty.bytes, "")
      local reference = Terminal.new({ columns = 20, rows = 3 })
      reference:write(streams[index])
      Assert.equal(Snapshot.encode(Terminal.state(target.terminal)), Snapshot.encode(Terminal.state(reference)))
      target.terminal:close(); reference:close()
    end
  end,
  output_service_rejects_invalid_limits_and_broken_reader_contracts = function()
    for _, bytes in ipairs({ 0, -1, 1.5, math.huge }) do
      Assert.equal(pcall(Service.new, { max_bytes = bytes, clock = function() return 0 end }), false)
    end
    Assert.equal(pcall(Service.new, {}), false)
    local service = Service.new({ max_bytes = 1, clock = function() return 0 end })
    local target = session("")
    target.pty.read_available = function() return "too long" end
    Assert.equal(pcall(service.drain, service, { target }, consume), false)
  end,
}
