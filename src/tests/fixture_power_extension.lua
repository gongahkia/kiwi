return function(api)
  api:register({
    after = { "terminal/glyph" },
    api_version = 1,
    encode = function(context)
      context.request_animation(0.1)
    end,
    extension = "power",
    name = "heartbeat",
    order = 25,
    reads = {},
    writes = {},
  })
end
