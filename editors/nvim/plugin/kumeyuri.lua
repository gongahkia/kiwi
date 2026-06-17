if vim.g.loaded_kumeyuri == 1 then
  return
end

vim.g.loaded_kumeyuri = 1
require("kumeyuri").setup()
