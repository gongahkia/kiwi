return {
  id = "sgr-colours",
  source = "XTerm Control Sequences: SGR colours and ECMA-48 SGR",
  columns = 5,
  rows = 1,
  input = "\27[31mR\27[1;94mB\27[38;5;196mI\27[38;2;1;2;3mT\27[0mD",
  expected = {
    rows = { "RBITD" },
    cursor = { column = 4, row = 0, pending_wrap = true },
    cells = {
      { column = 0, row = 0, fg = { kind = "indexed", index = 1 } },
      { column = 1, row = 0, fg = { kind = "indexed", index = 12 }, flags = 1 },
      { column = 2, row = 0, fg = { kind = "indexed", index = 196 } },
      { column = 3, row = 0, fg = { kind = "rgb", red = 1, green = 2, blue = 3 } },
      { column = 4, row = 0, default_fg = true, flags = 0 },
    },
  },
}
