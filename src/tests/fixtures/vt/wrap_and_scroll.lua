return {
  id = "wrap-and-scroll",
  source = "XTerm Control Sequences: DECAWM and IND",
  columns = 3,
  rows = 2,
  input = "ABCDEF\r\nG\r\nH",
  expected = {
    rows = { "G  ", "H  " },
    cursor = { column = 1, row = 1 },
    scrollback_lines = 2,
  },
}
