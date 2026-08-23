return {
  id = "reverse-screen",
  source = "XTerm Control Sequences: DECSET 5 (DECSCNM reverse video) and CSI ! p (DECSTR)",
  columns = 4,
  rows = 1,
  input = "A\27[?5hB\27[!pC",
  expected = {
    rows = { "CB  " },
    cursor = { column = 1, row = 0 },
    modes = { reverse_video = false },
  },
}
