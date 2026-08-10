return {
  id = "cursor-style-and-sync",
  source = "XTerm Control Sequences: DECSCUSR; DECSET/DECRST 2026 synchronized output",
  columns = 5,
  rows = 2,
  input = "P\27[?2026h\27[?2026h\27[3 q\27[?1049hA\27[?1049l\27[6 q\27[?2026l",
  expected = {
    rows = { "P    ", "     " },
    cursor = { column = 1, row = 0 },
    active_screen = "primary",
    modes = { cursor_style = 6, synchronized_output = false },
  },
}
