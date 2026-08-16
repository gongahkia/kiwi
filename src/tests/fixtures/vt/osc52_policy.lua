return {
  id = "osc52-policy",
  source = "XTerm OSC 52 selection data; Kiwi default-deny and payload-bound policy",
  columns = 3,
  rows = 1,
  input = "\27]52;c;SGVsbG8=\27\\A\27]52;c;AAAAAAAAAAAAAAAA\27\\B",
  parser_options = { max_string_bytes = 16 },
  expected = {
    rows = { "AB " },
    cursor = { column = 2, row = 0 },
    parser = { ignored = 1 },
    unknown = { osc = 1 },
  },
}
