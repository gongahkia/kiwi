return {
  id = "dec-special-graphics",
  source = "VT100 character-set designation with G0/G1 shift controls",
  columns = 8,
  rows = 2,
  input = "\27(0lqk\27)0\14x\15x\27(Bx",
  expected = {
    rows = { "┌─┐││x  ", "        " },
    cursor = { column = 6, row = 0 },
  },
}
