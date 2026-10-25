local Assert = require("tests.assert")
local Terminal = require("kiwi.session.terminal")
local Transaction = require("kiwi.terminal.state_transaction")
local Hints = require("kiwi.input.hints")
local function fixture(text, columns, rows, history)
  local terminal = Terminal.new({ columns = columns or 80, rows = rows or 8,
    state_options = { scrollback_limit = history or 100 } })
  terminal:write(text)
  return Terminal.state(terminal), terminal
end
local function finish(state, budget)
  local ticks = 0
  while state:hints_pending() do
    state:hints_step(budget or 13)
    Assert.truthy(state.hints.last_step_work <= (budget or 13))
    ticks = ticks + 1; assert(ticks < 100000)
  end
end
return {
  hints_charge_long_uri_validation_to_the_budget_and_reuse_validated_ids = function()
    local uri = "https://e.test/" .. string.rep("x", 1900)
    local parts = {}
    for index = 1, 64 do parts[#parts + 1] = "\27]8;;" .. uri .. index .. "\27\\x\27]8;;\27\\" end
    local state = fixture(table.concat(parts), 80, 2)
    state:hints_begin(); Assert.truthy(state:hints_pending())
    Assert.truthy(#state.hints.matches < 4)
    finish(state, 31)
    Assert.equal(#state.hints.matches, 64)
    local repeat_link = "\27]8;id=shared;" .. uri .. "\27\\x\27]8;;\27\\ "
    state = fixture(string.rep(repeat_link, 64), 80, 2)
    state:hints_begin()
    Assert.equal(state:hints_pending(), false)
    Assert.equal(#state.hints.matches, 64)
    Assert.truthy(state.hints.last_step_work < 2500)
  end,
  hints_report_match_and_scan_limits_without_truncated_targets = function()
    local state = fixture(string.rep("https://e.test ", 300), 100, 80)
    state:hints_begin(); finish(state)
    Assert.equal(#state.hints.matches, Hints.maximum_matches)
    Assert.equal(state.hints.status, "match-limit")
    Assert.truthy(state:hints_view().truncated)
    local maximum = Hints.maximum_work
    Hints.maximum_work = 12
    local ok, message = xpcall(function()
      state:hints_begin()
      Assert.equal(state.hints.status, "scan-limit")
      Assert.equal(#state.hints.matches, 0)
      Assert.equal(state.hints:target(state), nil)
    end, debug.traceback)
    Hints.maximum_work = maximum
    assert(ok, message)
  end,
  hints_do_not_extend_a_plain_url_into_an_explicit_link_or_hard_break = function()
    local state = fixture("https://first.test\27]8;;https://actual.test\27\\/redirect\27]8;;\27\\\r\nhttps://second.test")
    state:hints_begin(); finish(state)
    Assert.equal(#state.hints.matches, 2)
    Assert.equal(state.hints.matches[1].uri, "https://actual.test")
    Assert.equal(state.hints.matches[2].uri, "https://second.test")
  end,
  hints_detect_web_mailto_balanced_punctuation_and_preserve_source_spelling = function()
    local state = fixture('See (HTTPS://example.com/a(b)). https://[::1]:80/x?q=1&n=2; mailto:a@example.com! nopehttps://bad.test')
    state:hints_begin(); finish(state)
    local matches = state.hints.matches
    Assert.equal(#matches, 3)
    Assert.equal(matches[1].uri, "HTTPS://example.com/a(b)")
    Assert.equal(matches[2].uri, "https://[::1]:80/x?q=1&n=2")
    Assert.equal(matches[3].uri, "mailto:a@example.com")
    local label = state.hints:labels(state)[2]
    Assert.truthy(state.hints:append(state, label.code))
    Assert.equal(state.hints:target(state).uri, matches[2].uri)
  end,
  hints_use_complete_urls_across_soft_wraps_and_viewport_boundaries = function()
    local uri = "https://example.com/" .. string.rep("a", 70)
    local state = fixture(uri .. "\r\nafter\r\nafter", 20, 2)
    state:scroll_history(2)
    state:hints_begin(); finish(state)
    Assert.equal(#state.hints.matches, 1)
    Assert.equal(state.hints.matches[1].uri, uri)
    Assert.equal(state.hints.matches[1].first, 0)
    local hard = fixture("https://abc\r\n.test/path", 30, 2)
    hard:hints_begin(); finish(hard)
    Assert.equal(hard.hints.matches[1].uri, "https://abc")
  end,
  hints_reject_oversized_tokens_and_unsupported_schemes = function()
    local state = fixture("https://a/" .. string.rep("x", 2100) .. " file:///tmp/a javascript:bad https:// mailto: ", 100, 24)
    state:hints_begin(); finish(state)
    Assert.equal(#state.hints.matches, 0)
  end,
  hints_prefer_explicit_osc8_targets_over_the_displayed_url = function()
    local state = fixture("\27]8;;https://actual.example\27\\https://display.example\27]8;;\27\\ next https://plain.example")
    state:hints_begin("copy"); finish(state)
    Assert.equal(#state.hints.matches, 2)
    Assert.equal(state.hints.matches[1].uri, "https://actual.example")
    Assert.equal(state.hints.matches[1].kind, "osc8")
    Assert.equal(state.hints.matches[2].uri, "https://plain.example")
  end,
  hints_assign_unique_labels_and_page_dense_single_cell_links = function()
    local parts = {}
    for index = 1, 40 do parts[#parts + 1] = "\27]8;;https://e.test/" .. index .. "\27\\x\27]8;;\27\\" end
    local state = fixture(table.concat(parts), 80, 2)
    state:hints_begin(); finish(state)
    Assert.equal(#state.hints.matches, 40)
    Assert.equal(state:hints_view().pages, 2)
    Assert.equal(#state.hints:labels(state), #Hints.alphabet)
    state.hints:next_page(1)
    local labels = state.hints:labels(state)
    Assert.equal(#labels, 14)
    state.hints:append(state, labels[14].code)
    Assert.equal(state.hints:target(state).uri, "https://e.test/40")
    local plain = fixture(string.rep("https://e.test ", 40), 80, 10)
    plain:hints_begin(); finish(plain)
    local seen = {}
    for _, label in ipairs(plain.hints:labels(plain)) do
      Assert.equal(#label.code, 2); Assert.truthy(not seen[label.code]); seen[label.code] = true
    end
    Assert.equal(#plain.hints:labels(plain), 40)
  end,
  hints_cancel_stale_targets_after_output_viewport_resize_or_screen_changes = function()
    for _, kind in ipairs({ "output", "viewport", "resize", "screen" }) do
      local state, terminal = fixture("https://e.test\r\nline\r\nline", 30, 2)
      state:scroll_history(1); state:hints_begin(); finish(state)
      Assert.truthy(state.hints:target(state))
      if kind == "output" then terminal:write("x")
      elseif kind == "viewport" then state:scroll_history(-1)
      elseif kind == "resize" then terminal:resize(40, 3)
      else terminal:write("\27[?1049h") end
      Assert.equal(state.hints:target(state), nil)
      Assert.equal(#state.hints:labels(state), 0)
    end
  end,
  hints_scan_jobs_are_bounded_and_transactionally_independent = function()
    local state = fixture(string.rep("a", 6000) .. " https://e.test ", 100, 70)
    state:hints_begin(); Assert.truthy(state:hints_pending())
    local work = state.hints.job.work
    local transaction = Transaction.new(state, { columns = 100, rows = 70 })
    finish(transaction.state, 17)
    Assert.equal(#transaction.state.hints.matches, 1)
    Assert.equal(state.hints.job.work, work)
    state.hints:clear(); Assert.equal(state:hints_pending(), false)
  end,
}
