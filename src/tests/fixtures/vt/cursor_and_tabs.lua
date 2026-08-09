return {
  id = "cursor-and-tabs",
  source = "XTerm Control Sequences: CUU/CUD/CUP and HT",
  columns = 12,
  rows = 3,
  input = "A\tB\27[2;4H!\27[1A^",
  expected = {
    rows = { "A   ^   B   ", "   !        ", "            " },
    cursor = { column = 5, row = 0 },
  },
}
