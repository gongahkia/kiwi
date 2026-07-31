local assertions = require("support.assertions")
local Builtins = require("shell.builtins")
local Registry = require("shell.registry")
local Session = require("shell.session")

local names = { "a", "b", "c" }
local data = { "", "x", "\0", "\255", "two words" }

local function make_session()
  local registry = assert(Registry.new())
  assert(Builtins.register(registry))
  return assert(Session.new(registry, {
    granted_capabilities = { "vfs.read", "vfs.write", "vfs.chdir" },
  }))
end

local function snapshot(session)
  local status = session:status().filesystem
  local result = { status.cwd, tostring(status.nodes), tostring(status.retained_file_bytes) }
  for _, name in ipairs(names) do
    local outcome = assert(session:dispatch("cat /" .. name))
    if not outcome.failed then
      local events = assert(outcome.invocation:poll()).events
      result[#result + 1] = name .. ":" .. (events[1] and events[1].data or "")
    end
  end
  return table.concat(result, "|")
end

return {
  {
    name = "property generated sandbox built-in commands preserve atomic virtual filesystem state",
    run = function()
      for iteration = 1, 96 do
        local sandbox = make_session()
        for _ = 1, 48 do
          local name = names[math.random(1, #names)]
          local before = snapshot(sandbox)
          local choice = math.random(1, 4)
          local outcome
          if choice == 1 then
            outcome = assert(
              sandbox:dispatch(
                "write /"
                  .. name
                  .. ' "'
                  .. data[math.random(1, #data)]:gsub('[\\"]', "\\%0")
                  .. '"'
              )
            )
          elseif choice == 2 then
            outcome = assert(sandbox:dispatch("rm /" .. name))
          elseif choice == 3 then
            outcome = assert(sandbox:dispatch("mkdir /" .. name))
          else
            outcome =
              assert(sandbox:dispatch("mv /" .. name .. " /" .. names[math.random(1, #names)]))
          end
          local status = sandbox:status().filesystem
          assertions.truthy(status.nodes <= 1024, "nodes iteration " .. iteration)
          assertions.truthy(status.retained_file_bytes <= 65536, "bytes iteration " .. iteration)
          if outcome.failed then
            assertions.equal(before, snapshot(sandbox), "atomic iteration " .. iteration)
          end
        end
      end
    end,
  },
}
