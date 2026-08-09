return {
  id = "utf8-and-malformed",
  source = "Unicode UTF-8 and XTerm malformed-sequence recovery",
  columns = 5,
  rows = 1,
  input = "€\195X\27[1;2;3H!",
  parser_options = { max_parameters = 2 },
  expected = {
    rows = { "€�X! " },
    cursor = { column = 4, row = 0 },
    parser = { ignored = 1 },
    unknown = { csi = 1 },
  },
}
