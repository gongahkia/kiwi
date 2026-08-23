local Assert = require("tests.assert")
local Group = require("kiwi.app.gtk_native_tab_group")

local function window(log)
  return {
    request_close = function() log[#log + 1] = "request-close" end,
  }
end

local function session(name, log, close_result, close_reason)
  return {
    window = {
      close_native_tab = function()
        log[#log + 1] = name .. ":detach"
        return close_result, close_reason
      end,
    },
    shutdown = function(self)
      self.closed = true
      log[#log + 1] = name .. ":shutdown"
    end,
  }
end

return {
  gtk_native_tab_group_detaches_before_releasing_a_nonfinal_session = function()
    local log = {}
    local group = Group.new(window(log))
    local first = session("first", log, true)
    local second = session("second", log, true)
    group:add(first)
    group:add(second)

    Assert.truthy(group:close(second))
    Assert.equal(table.concat(log, ","), "second:detach,second:shutdown")
    Assert.equal(#group.sessions, 1)
    Assert.truthy(group:contains(first))
    Assert.truthy(not group:contains(second))
    Assert.truthy(second.closed)
  end,
  gtk_native_tab_group_preserves_a_session_when_gtk_rejects_its_page_close = function()
    local log = {}
    local group = Group.new(window(log))
    local first = session("first", log, true)
    local second = session("second", log, false, "native-page-refused")
    group:add(first)
    group:add(second)

    local closed, reason = group:close(second)
    Assert.equal(closed, false)
    Assert.equal(reason, "native-page-refused")
    Assert.equal(table.concat(log, ","), "second:detach")
    Assert.equal(#group.sessions, 2)
    Assert.truthy(not second.closed)
  end,
  gtk_native_tab_group_closes_the_host_instead_of_removing_its_final_page = function()
    local log = {}
    local group = Group.new(window(log))
    local only = session("only", log, true)
    group:add(only)

    Assert.truthy(group:close(only))
    Assert.equal(table.concat(log, ","), "only:shutdown,request-close")
    Assert.equal(#group.sessions, 0)
    Assert.truthy(only.closed)
  end,
}
