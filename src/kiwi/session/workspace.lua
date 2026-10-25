local Workspace = {}
Workspace.__index = Workspace

local function assert_positive_integer(value, name)
  assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " must be a positive integer")
end

local function leaf(id)
  return { kind = "leaf", pane_id = id }
end

local function pane_count(node)
  if node.kind == "leaf" then return 1 end
  return pane_count(node.first) + pane_count(node.second)
end

local function minimum_dimensions(node)
  if node.kind == "leaf" then return 1, 1 end
  local first_width, first_height = minimum_dimensions(node.first)
  local second_width, second_height = minimum_dimensions(node.second)
  if node.direction == "vertical" then
    return first_width + second_width, math.max(first_height, second_height)
  end
  return math.max(first_width, second_width), first_height + second_height
end

local function node_snapshot(node)
  if node.kind == "leaf" then return { kind = "leaf", pane_id = node.pane_id } end
  return {
    kind = "split",
    direction = node.direction,
    ratio = node.ratio,
    first = node_snapshot(node.first),
    second = node_snapshot(node.second),
  }
end

function Workspace.new(options)
  options = options or {}
  local self = setmetatable({
    active_tab_id = nil,
    next_pane_id = 0,
    next_tab_id = 0,
    panes = {},
    tabs = {},
    maximum_panes = options.maximum_panes or 64,
    maximum_tabs = options.maximum_tabs or 32,
    on_close = options.on_close,
  }, Workspace)
  assert_positive_integer(self.maximum_panes, "workspace maximum panes")
  assert_positive_integer(self.maximum_tabs, "workspace maximum tabs")
  assert(self.on_close == nil or type(self.on_close) == "function", "workspace close callback must be a function")
  return self
end

local function restore_node(node, workspace, tab, new_session, pane_ids, depth)
  assert(type(node) == "table" and depth <= 64, "workspace snapshot has an invalid layout tree")
  if node.kind == "leaf" then
    assert_positive_integer(node.pane_id, "workspace snapshot pane id")
    assert(pane_ids[node.pane_id] == nil, "workspace snapshot reuses a pane id")
    local session = assert(new_session(node.pane_id, tab.id), "workspace session factory returned nil")
    local pane = { id = node.pane_id, session = session, tab_id = tab.id }
    workspace.panes[pane.id] = pane
    pane_ids[pane.id] = true
    workspace.next_pane_id = math.max(workspace.next_pane_id, pane.id)
    return leaf(pane.id)
  end
  assert(node.kind == "split" and (node.direction == "vertical" or node.direction == "horizontal"), "workspace snapshot has an invalid split")
  assert(type(node.ratio) == "number" and node.ratio >= 0.1 and node.ratio <= 0.9, "workspace snapshot has an invalid split ratio")
  local restored = {
    direction = node.direction,
    kind = "split",
    ratio = node.ratio,
  }
  restored.first = restore_node(node.first, workspace, tab, new_session, pane_ids, depth + 1)
  restored.second = restore_node(node.second, workspace, tab, new_session, pane_ids, depth + 1)
  restored.first.parent = restored
  restored.second.parent = restored
  return restored
end

function Workspace.restore(snapshot, new_session, options)
  assert(type(snapshot) == "table" and type(snapshot.tabs) == "table", "workspace restore needs a snapshot")
  assert(type(new_session) == "function", "workspace restore needs a session factory")
  local workspace = Workspace.new(options)
  assert_positive_integer(snapshot.active_tab_id, "workspace snapshot active tab id")
  local pane_ids = {}
  for _, item in ipairs(snapshot.tabs) do
    assert(type(item) == "table", "workspace snapshot has an invalid tab")
    assert_positive_integer(item.id, "workspace snapshot tab id")
    assert_positive_integer(item.active_pane_id, "workspace snapshot active pane id")
    assert(workspace:tab(item.id) == nil, "workspace snapshot reuses a tab id")
    assert(workspace:tab_count() < workspace.maximum_tabs, "workspace snapshot exceeds the tab limit")
    local tab = { active_pane_id = item.active_pane_id, id = item.id }
    tab.root = restore_node(item.root, workspace, tab, new_session, pane_ids, 0)
    assert(workspace.panes[tab.active_pane_id] and workspace.panes[tab.active_pane_id].tab_id == tab.id, "workspace snapshot active pane is outside its tab")
    workspace.tabs[#workspace.tabs + 1] = tab
    workspace.next_tab_id = math.max(workspace.next_tab_id, tab.id)
  end
  assert(workspace:tab(snapshot.active_tab_id) ~= nil, "workspace snapshot active tab is unknown")
  assert(workspace:pane_count() <= workspace.maximum_panes, "workspace snapshot exceeds the pane limit")
  workspace.active_tab_id = snapshot.active_tab_id
  return workspace
end

function Workspace:tab_count()
  return #self.tabs
end

function Workspace:pane_count()
  local count = 0
  for _ in pairs(self.panes) do count = count + 1 end
  return count
end

function Workspace:active_tab()
  if self.active_tab_id == nil then return nil end
  for _, tab in ipairs(self.tabs) do
    if tab.id == self.active_tab_id then return tab end
  end
end

function Workspace:tab(id)
  for _, tab in ipairs(self.tabs) do
    if tab.id == id then return tab end
  end
end

function Workspace:active_pane()
  local tab = self:active_tab()
  return tab and self.panes[tab.active_pane_id] or nil
end

function Workspace:new_tab(session)
  if self:tab_count() >= self.maximum_tabs then return nil, "tab-limit" end
  if self:pane_count() >= self.maximum_panes then return nil, "pane-limit" end
  self.next_tab_id = self.next_tab_id + 1
  self.next_pane_id = self.next_pane_id + 1
  local pane = { id = self.next_pane_id, session = session, tab_id = self.next_tab_id }
  local tab = {
    active_pane_id = pane.id,
    id = self.next_tab_id,
    root = leaf(pane.id),
  }
  self.panes[pane.id] = pane
  self.tabs[#self.tabs + 1] = tab
  self.active_tab_id = tab.id
  return pane, tab
end

function Workspace:focus_tab(id)
  for _, tab in ipairs(self.tabs) do
    if tab.id == id then
      self.active_tab_id = id
      return true
    end
  end
  return nil, "unknown-tab"
end

function Workspace:focus_pane(id)
  local pane = self.panes[id]
  if pane == nil then return nil, "unknown-pane" end
  local focused = assert(self:focus_tab(pane.tab_id))
  local tab = self:active_tab()
  tab.active_pane_id = pane.id
  return focused
end

local function find_leaf(node, pane_id)
  if node.kind == "leaf" then return node.pane_id == pane_id and node or nil end
  return find_leaf(node.first, pane_id) or find_leaf(node.second, pane_id)
end

local function replace_child(parent, previous, replacement)
  if parent == nil then return end
  if parent.first == previous then
    parent.first = replacement
  else
    assert(parent.second == previous, "workspace tree parent mismatch")
    parent.second = replacement
  end
  replacement.parent = parent
end

function Workspace:split(direction, session, options)
  options = options or {}
  assert(direction == "vertical" or direction == "horizontal", "workspace split direction must be vertical or horizontal")
  if self:pane_count() >= self.maximum_panes then return nil, "pane-limit" end
  local tab = self:active_tab()
  if tab == nil then return nil, "no-active-tab" end
  local target = assert(find_leaf(tab.root, tab.active_pane_id), "active pane is not in tab tree")
  local ratio = options.ratio or 0.5
  assert(type(ratio) == "number" and ratio >= 0.1 and ratio <= 0.9, "workspace split ratio must be between 0.1 and 0.9")
  self.next_pane_id = self.next_pane_id + 1
  local pane = { id = self.next_pane_id, session = session, tab_id = tab.id }
  self.panes[pane.id] = pane
  local sibling = leaf(pane.id)
  local split = {
    direction = direction,
    first = target,
    second = sibling,
    kind = "split",
    ratio = ratio,
  }
  local parent = target.parent
  target.parent = split
  sibling.parent = split
  split.parent = parent
  if parent == nil then
    tab.root = split
  else
    replace_child(parent, target, split)
  end
  tab.active_pane_id = pane.id
  tab.zoomed = false
  return pane
end

local function collect_leaves(node, output)
  if node.kind == "leaf" then
    output[#output + 1] = node
    return
  end
  collect_leaves(node.first, output)
  collect_leaves(node.second, output)
end

function Workspace:close_pane(id)
  local pane = self.panes[id]
  if pane == nil then return nil, "unknown-pane" end
  local tab
  for _, candidate in ipairs(self.tabs) do
    if candidate.id == pane.tab_id then tab = candidate break end
  end
  assert(tab, "workspace pane has no tab")
  tab.zoomed = false
  if pane_count(tab.root) == 1 then return nil, "last-pane" end
  local target = assert(find_leaf(tab.root, id), "workspace pane is not in tab tree")
  local parent = assert(target.parent, "workspace non-root pane has no parent")
  local sibling = parent.first == target and parent.second or parent.first
  local grandparent = parent.parent
  if grandparent == nil then
    tab.root = sibling
    sibling.parent = nil
  else
    replace_child(grandparent, parent, sibling)
  end
  self.panes[id] = nil
  if self.on_close then self.on_close(pane.session, { pane_id = id, tab_id = tab.id }) end
  if tab.active_pane_id == id then
    local remaining = {}
    collect_leaves(sibling, remaining)
    tab.active_pane_id = remaining[1].pane_id
  end
  return true
end

-- Removes a pane without closing its session. Hosts use this when transferring a
-- live PTY to another workspace; ordinary close_pane remains the destructive API.
function Workspace:detach_pane(id)
  local pane = self.panes[id]
  if pane == nil then return nil, "unknown-pane" end
  local tab = assert(self:tab(pane.tab_id), "workspace pane has no tab")
  tab.zoomed = false
  local target = assert(find_leaf(tab.root, id), "workspace pane is not in tab tree")
  local removed_tab = false
  if pane_count(tab.root) == 1 then
    for index, candidate in ipairs(self.tabs) do
      if candidate == tab then
        table.remove(self.tabs, index)
        break
      end
    end
    if self.active_tab_id == tab.id then
      local replacement = self.tabs[1]
      self.active_tab_id = replacement and replacement.id or nil
    end
    removed_tab = true
  else
    local parent = assert(target.parent, "workspace non-root pane has no parent")
    local sibling = parent.first == target and parent.second or parent.first
    local grandparent = parent.parent
    if grandparent == nil then
      tab.root = sibling
      sibling.parent = nil
    else
      replace_child(grandparent, parent, sibling)
    end
    if tab.active_pane_id == id then
      local leaves = {}
      collect_leaves(sibling, leaves)
      tab.active_pane_id = leaves[1].pane_id
    end
  end
  self.panes[id] = nil
  pane.tab_id = nil
  return pane, { removed_tab = removed_tab, tab_id = tab.id }
end

function Workspace:adopt_tab(session)
  return self:new_tab(session)
end

function Workspace:adopt_split(tab_id, direction, session, options)
  local target = self:tab(tab_id)
  if target == nil then return nil, "unknown-tab" end
  local previous = self.active_tab_id
  self.active_tab_id = target.id
  local pane, reason = self:split(direction, session, options)
  if pane == nil then self.active_tab_id = previous end
  return pane, reason
end

function Workspace:close_tab(id)
  local index
  for candidate_index, tab in ipairs(self.tabs) do
    if tab.id == id then index = candidate_index break end
  end
  if index == nil then return nil, "unknown-tab" end
  local tab = self.tabs[index]
  local leaves = {}
  collect_leaves(tab.root, leaves)
  for _, item in ipairs(leaves) do
    local pane = self.panes[item.pane_id]
    self.panes[item.pane_id] = nil
    if self.on_close then self.on_close(pane.session, { pane_id = pane.id, tab_id = tab.id }) end
  end
  table.remove(self.tabs, index)
  if self.active_tab_id == id then
    local replacement = self.tabs[math.min(index, #self.tabs)]
    self.active_tab_id = replacement and replacement.id or nil
  end
  return true
end

function Workspace:set_split_ratio(pane_id, ratio)
  assert(type(ratio) == "number" and ratio >= 0.1 and ratio <= 0.9, "workspace split ratio must be between 0.1 and 0.9")
  local pane = self.panes[pane_id]
  if pane == nil then return nil, "unknown-pane" end
  local tab = assert(self:tab(pane.tab_id), "workspace pane has no tab")
  local leaf_node = assert(find_leaf(tab.root, pane_id))
  local split = leaf_node.parent
  if split == nil then return nil, "unsplit-pane" end
  split.ratio = ratio
  return true
end

function Workspace:fits(width, height)
  for _, tab in ipairs(self.tabs) do
    local minimum_width, minimum_height = minimum_dimensions(tab.root)
    if width < minimum_width or height < minimum_height then return false end
  end
  return true
end

function Workspace:can_split(direction, width, height)
  assert(direction == "vertical" or direction == "horizontal", "invalid split direction")
  if self:pane_count() >= self.maximum_panes then return nil, "pane-limit" end
  local layout = self:layout(width, height, true)
  if layout == nil then return nil, "insufficient-space" end
  for _, pane in ipairs(layout) do
    if pane.active then
      if (direction == "vertical" and pane.width or pane.height) < 2 then return nil, "insufficient-space" end
      return true
    end
  end
  return nil, "no-active-pane"
end

function Workspace:layout(width, height, unzoomed)
  assert(type(width) == "number" and width >= 1 and width % 1 == 0, "workspace width must be a positive integer")
  assert(type(height) == "number" and height >= 1 and height % 1 == 0, "workspace height must be a positive integer")
  local tab = self:active_tab()
  if tab == nil then return {} end
  if tab.zoomed and not unzoomed then
    return {{ active = true, height = height, pane_id = tab.active_pane_id, width = width, x = 0, y = 0 }}
  end
  local minimum_width, minimum_height = minimum_dimensions(tab.root)
  if width < minimum_width or height < minimum_height then return nil, "insufficient-space" end
  local result = {}
  local function visit(node, x, y, available_width, available_height)
    if node.kind == "leaf" then
      result[#result + 1] = {
        active = tab.active_pane_id == node.pane_id,
        height = available_height,
        pane_id = node.pane_id,
        width = available_width,
        x = x,
        y = y,
      }
      return
    end
    if node.direction == "vertical" then
      local first_minimum_width = minimum_dimensions(node.first)
      local second_minimum_width = minimum_dimensions(node.second)
      local first_width = math.max(first_minimum_width, math.min(available_width - second_minimum_width, math.floor(available_width * node.ratio + 0.5)))
      visit(node.first, x, y, first_width, available_height)
      visit(node.second, x + first_width, y, available_width - first_width, available_height)
    else
      local _, first_minimum_height = minimum_dimensions(node.first)
      local _, second_minimum_height = minimum_dimensions(node.second)
      local first_height = math.max(first_minimum_height, math.min(available_height - second_minimum_height, math.floor(available_height * node.ratio + 0.5)))
      visit(node.first, x, y, available_width, first_height)
      visit(node.second, x, y + first_height, available_width, available_height - first_height)
    end
  end
  visit(tab.root, 0, 0, width, height)
  return result
end

function Workspace:focus_relative_tab(offset)
  assert(offset == 1 or offset == -1, "tab offset must be 1 or -1")
  if #self.tabs < 2 then return false end
  for index, tab in ipairs(self.tabs) do
    if tab.id == self.active_tab_id then
      return self:focus_tab(self.tabs[(index - 1 + offset) % #self.tabs + 1].id)
    end
  end
  return false
end

function Workspace:focus_relative_pane(offset)
  assert(offset == 1 or offset == -1, "pane offset must be 1 or -1")
  local tab = self:active_tab()
  if tab == nil then return false end
  local leaves = {}
  collect_leaves(tab.root, leaves)
  if #leaves < 2 then return false end
  for index, node in ipairs(leaves) do
    if node.pane_id == tab.active_pane_id then
      return self:focus_pane(leaves[(index - 1 + offset) % #leaves + 1].pane_id)
    end
  end
  return false
end

local function horizontal_direction(direction)
  assert(direction == "left" or direction == "right" or direction == "up" or direction == "down", "invalid pane direction")
  return direction == "left" or direction == "right"
end

function Workspace:focus_direction(direction, width, height)
  local horizontal = horizontal_direction(direction)
  local layout = self:layout(width, height, true)
  if layout == nil then return false end
  local active
  for _, pane in ipairs(layout) do if pane.active then active = pane break end end
  if active == nil then return false end
  local best, best_gap, best_alignment
  for _, pane in ipairs(layout) do
    if not pane.active then
      local gap
      if direction == "left" then gap = active.x - pane.x - pane.width
      elseif direction == "right" then gap = pane.x - active.x - active.width
      elseif direction == "up" then gap = active.y - pane.y - pane.height
      else gap = pane.y - active.y - active.height end
      local start = horizontal and pane.y or pane.x
      local size = horizontal and pane.height or pane.width
      local active_start = horizontal and active.y or active.x
      local active_size = horizontal and active.height or active.width
      local overlap = math.min(start + size, active_start + active_size) - math.max(start, active_start)
      local alignment = math.abs(start + size / 2 - active_start - active_size / 2)
      if gap >= 0 and overlap > 0 and (best == nil or gap < best_gap or (gap == best_gap and alignment < best_alignment)) then
        best, best_gap, best_alignment = pane, gap, alignment
      end
    end
  end
  return best ~= nil and self:focus_pane(best.pane_id) or false
end

function Workspace:toggle_zoom(width, height)
  local tab = self:active_tab()
  if tab == nil or pane_count(tab.root) < 2 then return false end
  if tab.zoomed and width ~= nil then
    local layout, reason = self:layout(width, height, true)
    if layout == nil then return nil, reason end
  end
  tab.zoomed = not tab.zoomed
  return true
end

function Workspace:resize_active_split(direction, cells, width, height)
  local horizontal = horizontal_direction(direction)
  assert_positive_integer(cells, "split resize cells")
  local tab = self:active_tab()
  if tab == nil or tab.zoomed then return false end
  local node = find_leaf(tab.root, tab.active_pane_id)
  local split = node and node.parent
  while split and (split.direction == "vertical") ~= horizontal do split = split.parent end
  if split == nil then return false end
  local layout = self:layout(width, height, true)
  if layout == nil then return false end
  local leaves, members = {}, {}
  collect_leaves(split, leaves)
  for _, leaf_node in ipairs(leaves) do members[leaf_node.pane_id] = true end
  local first, last = math.huge, 0
  for _, pane in ipairs(layout) do
    if members[pane.pane_id] then
      local start = horizontal and pane.x or pane.y
      first = math.min(first, start)
      last = math.max(last, start + (horizontal and pane.width or pane.height))
    end
  end
  local sign = (direction == "left" or direction == "up") and -1 or 1
  local ratio = math.max(0.1, math.min(0.9, split.ratio + sign * cells / (last - first)))
  if ratio == split.ratio then return false end
  split.ratio = ratio
  return true
end

function Workspace:equalize_splits()
  local tab = self:active_tab()
  if tab == nil then return false end
  local changed = false
  local function visit(node)
    if node.kind == "leaf" then return end
    if node.ratio ~= 0.5 then node.ratio, changed = 0.5, true end
    visit(node.first)
    visit(node.second)
  end
  visit(tab.root)
  return changed
end

function Workspace:pane_at(width, height, column, row)
  assert(type(column) == "number" and column % 1 == 0, "workspace hit-test column must be an integer")
  assert(type(row) == "number" and row % 1 == 0, "workspace hit-test row must be an integer")
  if column < 0 or row < 0 or column >= width or row >= height then return nil, "outside-workspace" end
  local layout, reason = self:layout(width, height)
  if layout == nil then return nil, reason end
  for _, pane in ipairs(layout) do
    if column >= pane.x and column < pane.x + pane.width and row >= pane.y and row < pane.y + pane.height then
      return self.panes[pane.pane_id], pane
    end
  end
  return nil, "outside-workspace"
end

function Workspace:snapshot()
  local tabs = {}
  for index, tab in ipairs(self.tabs) do
    tabs[index] = {
      active_pane_id = tab.active_pane_id,
      id = tab.id,
      pane_count = pane_count(tab.root),
      root = node_snapshot(tab.root),
    }
  end
  return { active_tab_id = self.active_tab_id, tabs = tabs }
end

return Workspace
