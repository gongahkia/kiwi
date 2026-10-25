-- Bounded Thompson NFA. No backtracking, native dependency or executable patterns.
-- Matches are leftmost-longest; offsets count Unicode scalar values, not bytes.
local Utf8 = require("kiwi.terminal.utf8")
local Regex = { maximum_bytes = 1024, maximum_states = 512, maximum_depth = 32, maximum_repeat = 128 }
local Runner = {}
Runner.__index = Runner

local function scalars(text)
  local values, valid = {}, true
  local decoder = Utf8.Decoder.new(function(codepoint, _, replaced)
    if replaced or codepoint == 0 then valid = false end
    values[#values + 1] = codepoint
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  if not valid then error("pattern must be NUL-free UTF-8", 0) end
  return values
end
Regex.scalars = scalars

local digit = { { 48, 57 } }
local word = { { 48, 57 }, { 65, 90 }, { 95, 95 }, { 97, 122 } }
local space = { { 9, 13 }, { 32, 32 } }
local classes = { d = digit, D = digit, w = word, W = word, s = space, S = space }
local function member(ranges, codepoint)
  local lower, upper = 1, #ranges
  while lower <= upper do
    local middle = math.floor((lower + upper) / 2)
    local range = ranges[middle]
    if codepoint < range[1] then upper = middle - 1
    elseif codepoint > range[2] then lower = middle + 1
    else return true end
  end
  return false
end
local function class_ranges(atoms)
  local ranges = {}
  for _, atom in ipairs(atoms) do
    if atom.negate then
      local start = 0
      for _, range in ipairs(atom.ranges) do
        if start < range[1] then ranges[#ranges + 1] = { start, range[1] - 1 } end
        start = range[2] + 1
      end
      if start <= 0x10ffff then ranges[#ranges + 1] = { start, 0x10ffff } end
    else
      for _, range in ipairs(atom.ranges) do ranges[#ranges + 1] = { range[1], range[2] } end
    end
  end
  table.sort(ranges, function(a, b) return a[1] < b[1] end)
  local merged = {}
  for _, range in ipairs(ranges) do
    local last = merged[#merged]
    if last and range[1] <= last[2] + 1 then last[2] = math.max(last[2], range[2])
    else merged[#merged + 1] = range end
  end
  return merged
end

local function is_word(codepoint) return codepoint ~= nil and member(word, codepoint) end

function Regex.compile(pattern, literal)
  if type(pattern) ~= "string" or #pattern > Regex.maximum_bytes then return nil, "pattern exceeds 1024 bytes" end
  local ok, result = pcall(function()
    local tokens = scalars(pattern)
    if literal then
      local prefix, matched = {}, 0
      prefix[1] = 0
      for index = 2, #tokens do
        while matched > 0 and tokens[index] ~= tokens[matched + 1] do matched = prefix[matched] end
        if tokens[index] == tokens[matched + 1] then matched = matched + 1 end
        prefix[index] = matched
      end
      return { literal = tokens, prefix = prefix }
    end
    local position, depth = 1, 0
    local function peek() return tokens[position] end
    local function take() local value = tokens[position]; position = position + 1; return value end
    local function failure(message) error(message .. " at character " .. position, 0) end
    local function escaped(in_class)
      local value = take()
      if not value then failure("unfinished escape") end
      local name = value < 128 and string.char(value) or ""
      if classes[name] then return { kind = "class", atoms = { { ranges = classes[name], negate = name:match("%u") ~= nil } } } end
      if not in_class and (name == "b" or name == "B") then return { kind = "boundary", negate = name == "B" } end
      local controls = { n = 10, r = 13, t = 9 }
      if controls[name] then return { kind = "char", value = controls[name] } end
      if value >= 48 and value <= 57 then failure("backreferences are unsupported") end
      if name:match("%a") then failure("unsupported escape") end
      return { kind = "char", value = value }
    end
    local expression
    local function atom()
      local value = take()
      if not value then failure("expected expression") end
      if value == 40 then -- (
        depth = depth + 1
        if depth > Regex.maximum_depth then failure("group nesting exceeds 32") end
        if peek() == 63 then
          take()
          if take() ~= 58 then failure("only plain and noncapturing groups are supported") end
        end
        local node = expression()
        if take() ~= 41 then failure("unclosed group") end
        depth = depth - 1
        return node
      elseif value == 91 then -- [
        local node = { kind = "class", atoms = {}, negate = peek() == 94 }
        if node.negate then take() end
        while peek() and peek() ~= 93 do
          local first = take()
          local item = first == 92 and escaped(true) or { kind = "char", value = first }
          if item.kind == "char" and peek() == 45 and tokens[position + 1] and tokens[position + 1] ~= 93 then
            take()
            local last = take()
            local finish = last == 92 and escaped(true) or { kind = "char", value = last }
            if finish.kind ~= "char" or item.value > finish.value then failure("invalid character range") end
            node.atoms[#node.atoms + 1] = { ranges = { { item.value, finish.value } } }
          elseif item.kind == "char" then
            node.atoms[#node.atoms + 1] = { ranges = { { item.value, item.value } } }
          else
            node.atoms[#node.atoms + 1] = item.atoms[1]
          end
        end
        if take() ~= 93 then failure("unclosed character class") end
        if #node.atoms == 0 then failure("empty character class") end
        return node
      elseif value == 92 then return escaped(false)
      elseif value == 46 then return { kind = "any" }
      elseif value == 94 then return { kind = "bol" }
      elseif value == 36 then return { kind = "eol" }
      elseif value == 42 or value == 43 or value == 63 or value == 123 or value == 125 or value == 41 then
        failure("unexpected metacharacter")
      end
      return { kind = "char", value = value }
    end
    local function number()
      local value, count = 0, 0
      while peek() and peek() >= 48 and peek() <= 57 do
        value, count = value * 10 + take() - 48, count + 1
        if value > Regex.maximum_repeat then failure("repeat count exceeds 128") end
      end
      if count == 0 then failure("expected repeat count") end
      return value
    end
    local function sequence()
      local nodes = {}
      while peek() and peek() ~= 41 and peek() ~= 124 do
        local node = atom()
        local quantifier = peek()
        local minimum, maximum
        if quantifier == 42 then minimum, maximum = 0, false; take()
        elseif quantifier == 43 then minimum, maximum = 1, false; take()
        elseif quantifier == 63 then minimum, maximum = 0, 1; take()
        elseif quantifier == 123 then
          take(); minimum = number(); maximum = minimum
          if peek() == 44 then take(); if peek() == 125 then maximum = false else maximum = number() end end
          if take() ~= 125 then failure("unclosed repeat count") end
          if maximum and maximum < minimum then failure("reversed repeat count") end
        end
        if minimum then node = { kind = "repeat", node = node, minimum = minimum, maximum = maximum } end
        nodes[#nodes + 1] = node
      end
      return { kind = "sequence", nodes = nodes }
    end
    expression = function()
      local nodes = { sequence() }
      while peek() == 124 do take(); nodes[#nodes + 1] = sequence() end
      return #nodes == 1 and nodes[1] or { kind = "alternate", nodes = nodes }
    end
    local ast = expression()
    if peek() then failure("unexpected closing group") end
    local states = {}
    local function emit(node)
      if #states >= Regex.maximum_states then failure("compiled expression exceeds 512 states") end
      states[#states + 1] = node
      return #states
    end
    local build
    build = function(node, following)
      if node.kind == "sequence" then
        for index = #node.nodes, 1, -1 do following = build(node.nodes[index], following) end
        return following
      elseif node.kind == "alternate" then
        local start = build(node.nodes[#node.nodes], following)
        for index = #node.nodes - 1, 1, -1 do start = emit({ kind = "split", out = build(node.nodes[index], following), other = start }) end
        return start
      elseif node.kind == "repeat" then
        local tail = following
        if node.maximum == false then
          local loop = emit({ kind = "split", other = following })
          states[loop].out = build(node.node, loop)
          tail = loop
        else
          for _ = 1, node.maximum - node.minimum do tail = emit({ kind = "split", out = build(node.node, tail), other = tail }) end
        end
        for _ = 1, node.minimum do tail = build(node.node, tail) end
        return tail
      end
      return emit({ kind = node.kind, value = node.value, ranges = node.atoms and class_ranges(node.atoms), negate = node.negate, out = following })
    end
    local finish = emit({ kind = "match" })
    return { start = build(ast, finish), states = states }
  end)
  if not ok then return nil, tostring(result) end
  return result
end

function Regex.runner(program, input, offset)
  return setmetatable({ program = program, input = input, position = offset or 1,
    matched = 0, frontier = {}, phase = "seed", steps = 0 }, Runner)
end

local function accepts(state, codepoint)
  if state.kind == "char" then return codepoint == state.value end
  if state.kind == "any" then return codepoint ~= 10 end
  local found = member(state.ranges, codepoint)
  if state.negate then return not found end
  return found
end

function Runner:finish()
  self.done = true
  return true, self.first, self.last
end

function Runner:step(budget)
  assert(type(budget) == "number" and budget >= 1 and budget % 1 == 0, "regex step budget must be positive")
  if self.done then return true, self.first, self.last, 0 end
  local used = 0
  while used < budget and not self.done do
    used, self.steps = used + 1, self.steps + 1
    local program, input, position = self.program, self.input, self.position
    if program.literal then
      local token = input[position]
      if #program.literal == 0 then self.first, self.last = position, position - 1; self:finish()
      elseif not token then self:finish()
      elseif self.matched > 0 and token ~= program.literal[self.matched + 1] then self.matched = program.prefix[self.matched]
      else
        if token == program.literal[self.matched + 1] then self.matched = self.matched + 1 end
        self.position = position + 1
        if self.matched == #program.literal then self.first, self.last = position - self.matched + 1, position; self:finish() end
      end
    elseif self.phase == "seed" then
      local seeds = {}
      for id, start in pairs(self.frontier) do seeds[#seeds + 1] = { id, start } end
      if not self.first then seeds[#seeds + 1] = { program.start, position } end
      -- Earliest starts visit each epsilon state first, so cycles and duplicate
      -- paths cost at most one visit per state at this input position.
      table.sort(seeds, function(a, b) return a[2] > b[2] end)
      self.stack, self.seen, self.consumers = seeds, {}, {}
      self.phase = "closure"
    elseif self.phase == "closure" then
      local item = table.remove(self.stack)
      if item then
        local id, start = item[1], item[2]
        if not self.seen[id] and (not self.first or start <= self.first) then
          self.seen[id] = true
          local state = program.states[id]
          local function push(target) self.stack[#self.stack + 1] = { target, start } end
          if state.kind == "split" then push(state.other); push(state.out)
          elseif state.kind == "bol" then if position == 1 then push(state.out) end
          elseif state.kind == "eol" then if position == #input + 1 then push(state.out) end
          elseif state.kind == "boundary" then
            local boundary = is_word(input[position - 1]) ~= is_word(input[position])
            if boundary ~= (state.negate == true) then push(state.out) end
          elseif state.kind == "match" then
            if not self.first or start < self.first or (start == self.first and position - 1 > self.last) then
              self.first, self.last = start, position - 1
            end
          else self.consumers[#self.consumers + 1] = { id, start } end
        end
      else
        self.frontier, self.consumer_index, self.phase = {}, 1, "advance"
        if position > #input then self:finish() end
      end
    else
      local item = self.consumers[self.consumer_index]
      if item then
        self.consumer_index = self.consumer_index + 1
        local state, start = program.states[item[1]], item[2]
        if (not self.first or start <= self.first) and accepts(state, input[position]) then
          local previous = self.frontier[state.out]
          if not previous or start < previous then self.frontier[state.out] = start end
        end
      elseif self.first and next(self.frontier) == nil then self:finish()
      else self.position, self.phase = position + 1, "seed" end
    end
  end
  return self.done == true, self.first, self.last, used
end

return Regex
