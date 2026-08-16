return {
  id = "left-right-margins",
  source = "VT420 DECSLRM/DECLRMM: rectangular scrolling and DECRQSS",
  columns = 8,
  rows = 4,
  input = "\27[1;1HABC123\27[2;1HDEF456\27[3;1HGHI789\27[?69h\27[2;4s\27[1;3r\27[S\27P$qs\27\\",
  expected = {
    rows = { "AEF423  ", "DHI756  ", "G   89  ", "        " },
    cursor = { column = 0, row = 0 },
    margins = { top = 0, bottom = 2, left = 1, right = 3 },
    modes = { left_right_margin = true },
    responses = { "\27P1$r2;4s\27\\" },
  },
}
