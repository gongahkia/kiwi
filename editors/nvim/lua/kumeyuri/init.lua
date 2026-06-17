local preview = require("kumeyuri.preview")

local M = {}

function M.setup(opts)
  preview.setup(opts)
end

function M.preview(opts)
  return preview.open(opts)
end

function M.close()
  preview.close()
end

return M
