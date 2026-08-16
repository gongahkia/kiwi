return {
  id = "dcs-status",
  source = "XTerm Control Sequences: bounded DECRQSS for SGR, DECSTBM, and DECSCUSR",
  columns = 8,
  rows = 5,
  input = "\27[1;3;4;38;5;120;48;2;1;2;3m\27P$qm\27\\\27[2;4r\27P$qr\27\\\27[5 q\27P$q q\27\\\27P$qx\27\\",
  expected = {
    cursor = { column = 0, row = 0 },
    margins = { top = 1, bottom = 3 },
    responses = {
      "\27P1$r1;3;4;38;5;120;48;2;1;2;3m\27\\",
      "\27P1$r2;4r\27\\",
      "\27P1$r5 q\27\\",
      "\27P0$r\27\\",
    },
  },
}
