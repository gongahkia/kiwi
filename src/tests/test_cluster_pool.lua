local Assert = require("tests.assert")
local Pool = require("kiwi.terminal.cluster_pool")
local Utf8 = require("kiwi.terminal.utf8")
local Terminal = require("kiwi.session.terminal")
local Transaction = require("kiwi.terminal.state_transaction")

return {
  cluster_pool_eviction_preserves_cell_owned_arrays_and_bounds_keys = function()
    local pool = Pool.new()
    local first = pool:intern("é", nil, 0xe9)
    Assert.equal(pool:intern("é", nil, 0xe9), first)
    for cp = 0x1000, 0x1000 + Pool.maximum_entries - 1 do pool:intern(Utf8.encode(cp), nil, cp) end
    Assert.equal(pool.count, Pool.maximum_entries)
    Assert.equal(#pool.order, Pool.maximum_entries)
    Assert.equal(pool.entries["é"], nil)
    local entries = 0
    for _ in pairs(pool.entries) do entries = entries + 1 end
    Assert.equal(entries, Pool.maximum_entries)
    Assert.equal(first[1], 0xe9)
    local replacement = pool:intern("é", nil, 0xe9)
    Assert.truthy(replacement ~= first)
    Assert.equal(replacement[1], first[1])
  end,
  cluster_pool_preserves_long_clusters_without_retaining_them = function()
    local pool, prefix = Pool.new(), {}
    for index = 1, Pool.maximum_codepoints do prefix[index] = 0x301 end
    local text = string.rep("́", Pool.maximum_codepoints + 1)
    local extended = pool:intern(text, prefix, 0x301)
    Assert.equal(#extended, Pool.maximum_codepoints + 1)
    Assert.equal(#prefix, Pool.maximum_codepoints)
    Assert.equal(pool.count, 0)
    Assert.equal(pool.entries[text], nil)
    -- The independent key-byte bound also applies to callers with short arrays.
    local oversized = string.rep("A", Pool.maximum_bytes + 1)
    Assert.equal(pool:intern(oversized, nil, 65)[1], 65)
    Assert.equal(pool.count, 0)
  end,
  shared_unicode_clusters_extend_without_changing_other_cells_or_transactions = function()
    local left = Terminal.new({ columns = 8, rows = 2, state_options = { scrollback_limit = 4 } })
    local right = Terminal.new({ columns = 8, rows = 2 })
    left:write("éé")
    right:write("é")
    local a, b = Terminal.state(left), Terminal.state(right)
    local original = a:get(0, 0).codepoints
    Assert.equal(a:get(1, 0).codepoints, original)
    Assert.equal(b:get(0, 0).codepoints, original)
    left:write("́")
    Assert.equal(a:get(1, 0).glyph, "é́")
    Assert.equal(#a:get(1, 0).codepoints, 2)
    Assert.equal(#original, 1)
    Assert.equal(b:get(0, 0).glyph, "é")
    local staged = Transaction.new(a)
    staged.state:write_codepoint("̀", 0x300)
    Assert.equal(#staged.state:get(1, 0).codepoints, 3)
    Assert.equal(#a:get(1, 0).codepoints, 2)
    a:scroll_up(1)
    right:write("́")
    Assert.equal(b:get(0, 0).glyph, "é́")
    Assert.equal(b:get(0, 0).codepoints, a.scrollback:get(1).cells[1].codepoints)
    left:close(); right:close()
  end,
  repeated_unicode_cluster_lookup_does_not_allocate_after_warmup = function()
    local pool = Pool.new()
    local prefix = { 0x65 }
    for _ = 1, 1000 do pool:intern("é", prefix, 0x301) end
    collectgarbage("collect"); collectgarbage("stop")
    local before = collectgarbage("count")
    local ok, message = xpcall(function()
      for _ = 1, 20000 do pool:intern("é", prefix, 0x301) end
      Assert.truthy(collectgarbage("count") - before < 128, "cached clusters allocated per lookup")
    end, debug.traceback)
    collectgarbage("restart")
    assert(ok, message)
    Assert.equal(#prefix, 1)
  end,
  repeated_unicode_history_bounds_retained_cluster_storage = function()
    local terminal = Terminal.new({ columns = 80, rows = 24, state_options = { scrollback_limit = 1024 } })
    local line = string.rep("é", 32) .. string.rep("é", 32) .. "\r\n"
    for _ = 1, 50 do terminal:write(line) end
    collectgarbage("collect")
    local before = collectgarbage("count")
    for _ = 1, 1074 do terminal:write(line) end
    collectgarbage("collect")
    local retained = collectgarbage("count") - before
    Assert.truthy(retained < 14 * 1024, "repeated Unicode history retained " .. retained .. " KiB")
    local state = Terminal.state(terminal)
    Assert.equal(state.scrollback:size(), 1024)
    local row = state.scrollback:get(1)
    Assert.equal(row.cells[0].glyph, "é")
    Assert.equal(row.cells[32].glyph, "é")
    Assert.equal(#row.cells[32].codepoints, 2)
    terminal:close()
  end,
}
