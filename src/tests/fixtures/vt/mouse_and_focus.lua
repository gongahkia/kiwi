return {
  id = "mouse-and-focus",
  source = "XTerm Control Sequences: DECSET/DECRST 1000, 1002, 1003, 1004, and 1006",
  columns = 5,
  rows = 2,
  input = "\27[?1002;1006;1004h\27[?1003h\27[?1049h\27[?1049l\27[?1003l\27[?1006;1002l\27c\27[?9999h",
  expected = {
    modes = { mouse_tracking = "none", mouse_sgr = false, focus_reporting = false },
    unknown = { csi = 1 },
  },
}
