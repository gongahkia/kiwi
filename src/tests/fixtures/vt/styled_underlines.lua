return {
  id = "styled-underlines",
  source = "Kitty styled/coloured underline protocol, SGR and DECRQSS round trip",
  columns = 8, rows = 1,
  input = "\27[4:1;58:5:1mA\27[4:2mB\27[4:3mC\27[4:4mD\27[4:5;58;2;12;171;52m \27P$qm\27\\\27[59;24mN",
  expected = {
    rows = { "ABCD N  " },
    cells = {
      { column = 0, row = 0, underline_style = 1 },
      { column = 1, row = 0, underline_style = 2 },
      { column = 2, row = 0, underline_style = 3 },
      { column = 3, row = 0, underline_style = 4 },
      { column = 4, row = 0, underline_style = 5, underline_color = { red = 12, green = 171, blue = 52 } },
      { column = 5, row = 0, flags = 0 },
    },
    responses = { "\27P1$r4:5;58:2::12:171:52m\27\\" },
    unknown = { csi = 0 },
  },
}
