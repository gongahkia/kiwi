local assertions = require("support.assertions")
local VirtualFS = require("shell.virtual_fs")

local names = { "a", "b", "c", "\255" }
local bytes = { "", "x", "\0", "\255", "ab" }

local function snapshot(filesystem)
  local status = filesystem:status()
  local entries = assert(filesystem:list("/", { max_entries = 64 }))
  local rendered = {}
  for _, name in ipairs(entries) do
    local node = assert(filesystem:stat("/" .. name))
    rendered[#rendered + 1] = name .. ":" .. node.kind
    if node.kind == "file" then
      rendered[#rendered + 1] = assert(filesystem:read_file("/" .. name))
    end
  end
  return table.concat(rendered, "|"), status.nodes, status.retained_file_bytes
end

return {
  {
    name = "property generated virtual filesystem failures retain exact logical state and bounds",
    run = function()
      for iteration = 1, 128 do
        local filesystem = assert(VirtualFS.new({
          limits = {
            max_directory_entries = 4,
            max_file_bytes = 8,
            max_files = 4,
            max_nodes = 8,
            max_total_file_bytes = 16,
          },
        }))
        for _ = 1, 64 do
          local name = names[math.random(1, #names)]
          local operation = math.random(1, 4)
          local before, nodes, retained = snapshot(filesystem)
          local result
          if operation == 1 then
            result = filesystem:write_file("/" .. name, bytes[math.random(1, #bytes)])
          elseif operation == 2 then
            result = filesystem:append_file("/" .. name, bytes[math.random(1, #bytes)])
          elseif operation == 3 then
            result = filesystem:remove("/" .. name)
          else
            result = filesystem:make_directory("/" .. name)
          end
          local status = filesystem:status()
          assertions.truthy(status.nodes <= 8, "nodes iteration " .. iteration)
          assertions.truthy(status.retained_file_bytes <= 16, "bytes iteration " .. iteration)
          if not result then
            local after, after_nodes, after_retained = snapshot(filesystem)
            assertions.equal(before, after, "state iteration " .. iteration)
            assertions.equal(nodes, after_nodes, "nodes iteration " .. iteration)
            assertions.equal(retained, after_retained, "bytes iteration " .. iteration)
          end
        end
      end
    end,
  },
}
