return {
  id = "margins-and-origin",
  source = "XTerm Control Sequences: DECSTBM and DECOM",
  columns = 4,
  rows = 4,
  input = "0\27[2;1H1\27[3;1H2\27[4;1H3\27[2;4r\27[?6h\27[1;1HX\27[?6l",
  expected = {
    rows = { "0   ", "X   ", "2   ", "3   " },
    cursor = { column = 0, row = 0 },
    margins = { top = 1, bottom = 3 },
    modes = { origin = false },
  },
}
