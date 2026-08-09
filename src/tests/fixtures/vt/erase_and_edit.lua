return {
  id = "erase-and-edit",
  source = "ECMA-48: ED, EL, ICH and DCH",
  columns = 7,
  rows = 2,
  input = "abcdef\27[2G\27[@X\27[5G\27[P\27[2JQ",
  expected = {
    rows = { "    Q  ", "       " },
    cursor = { column = 5, row = 0 },
  },
}
