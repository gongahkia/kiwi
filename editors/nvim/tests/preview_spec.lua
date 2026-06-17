vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/editors/nvim")

local preview = require("kumeyuri.preview")
local kumeyuri = require("kumeyuri")

local function expect_equal(name, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(name .. "\nactual: " .. vim.inspect(actual) .. "\nexpected: " .. vim.inspect(expected))
  end
end

expect_equal("default argv", preview._build_argv("/tmp/flow.mmd", {
  command = "kumeyuri",
}), { "kumeyuri", "play", "/tmp/flow.mmd" })

expect_equal("argv with cargo command", preview._build_argv("/tmp/flow.mmd", {
  command = { "cargo", "run", "-q", "-p", "kumeyuri-cli", "--" },
  speed = 1.25,
  loop = true,
}), { "cargo", "run", "-q", "-p", "kumeyuri-cli", "--", "play", "--speed", "1.25", "--loop", "/tmp/flow.mmd" })

expect_equal("fractional dimensions", preview._resolve_dimensions({
  width = 0.5,
  height = 0.5,
}, 100, 40), {
  width = 50,
  height = 20,
  col = 25,
  row = 10,
})

kumeyuri.setup({ command = "kumeyuri" })
if vim.fn.exists(":KumeyuriPreview") ~= 2 then
  error(":KumeyuriPreview was not registered")
end
if vim.fn.exists(":KumeyuriClose") ~= 2 then
  error(":KumeyuriClose was not registered")
end

print("ok")
