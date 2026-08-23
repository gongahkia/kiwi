-- Owns the relationship between independently running GtkGL terminal sessions
-- and libadwaita pages. The final session closes the host window; GTK never
-- receives a request to remove its final page.
local Group = {}
Group.__index = Group

local function session_index(sessions, needle)
  for index, session in ipairs(sessions) do
    if session == needle then return index end
  end
end

function Group.new(window)
  assert(type(window) == "table" and type(window.request_close) == "function",
    "GTK native tab group needs a host window")
  return setmetatable({ closing = {}, sessions = {}, window = window }, Group)
end

function Group:add(session)
  assert(type(session) == "table" and type(session.shutdown) == "function" and
    type(session.window) == "table" and type(session.window.close_native_tab) == "function",
    "GTK native tab group needs a closeable terminal session")
  assert(session_index(self.sessions, session) == nil, "GTK native tab group cannot add one session twice")
  self.sessions[#self.sessions + 1] = session
  return session
end

function Group:contains(session)
  return session_index(self.sessions, session) ~= nil
end

function Group:close(session)
  local index = session_index(self.sessions, session)
  if index == nil or session.closed then return false, "unknown-native-tab" end
  if self.closing[session] then return false, "native-tab-close-in-progress" end
  self.closing[session] = true

  if #self.sessions == 1 then
    session:shutdown()
    table.remove(self.sessions, index)
    self.closing[session] = nil
    self.window:request_close()
    return true
  end

  local closed, reason = session.window:close_native_tab()
  if not closed then
    self.closing[session] = nil
    return false, reason
  end
  session:shutdown()
  table.remove(self.sessions, index)
  self.closing[session] = nil
  return true
end

function Group:shutdown()
  for _, session in ipairs(self.sessions) do session:shutdown() end
  self.closing = {}
  self.sessions = {}
end

return Group
