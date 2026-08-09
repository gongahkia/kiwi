return {
  id = "alternate-and-modes",
  source = "XTerm Control Sequences: DECSET/DECRST 1049, 25, 2004 and DSR",
  columns = 5,
  rows = 2,
  input = "P\27[?1049hA\27[?25l\27[?2004h\27[5n\27[6n\27[?1049l",
  expected = {
    rows = { "P    ", "     " },
    cursor = { column = 1, row = 0 },
    active_screen = "primary",
    modes = { cursor_visible = false, bracketed_paste = true },
    responses = { "\27[0n", "\27[1;2R" },
  },
}
