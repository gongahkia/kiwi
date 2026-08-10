return function(api)
  api:register({
    after = { "terminal/glyph" },
    api_version = 1,
    encode = function()
      error("device-soak fixture disables this optional pass")
    end,
    extension = "soak",
    name = "toggle",
    order = 25,
    reads = {},
    writes = {},
  })
end
