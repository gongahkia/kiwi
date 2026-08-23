return {
  id = "xterm-reset-tab-modes",
  source = "XTerm Control Sequences: TBC, DECST8C, XTSAVE/XTRESTORE, and DECRQM",
  columns = 20,
  rows = 2,
  input = "\27[3g\27[?5W\27[1;1H\tA\27[1;1H\27H\27[1;1H\27[1g\27[1;1H\27[2g\t\27[3g\27[1;1H\t\27[?5W\27[1;1H\tC"
    .. "\27[?1;5;25;1004;1007;2004;2026h\27[?1;5;25;1004;1007;2004;2026s"
    .. "\27[?1;5;25;1004;1007;2004;2026l\27[?1;5;25;1004;1007;2004;2026r"
    .. "\27[?1$p\27[?5$p\27[?25$p\27[?1004$p\27[?1007$p\27[?2004$p\27[?2026$p",
  expected = {
    rows = { "        C           ", "                    " },
    cursor = { column = 9, row = 0 },
    modes = {
      alternate_scroll = true,
      application_cursor = true,
      bracketed_paste = true,
      cursor_visible = true,
      focus_reporting = true,
      reverse_video = true,
      synchronized_output = true,
    },
    responses = {
      "\27[?1;1$y",
      "\27[?5;1$y",
      "\27[?25;1$y",
      "\27[?1004;1$y",
      "\27[?1007;1$y",
      "\27[?2004;1$y",
      "\27[?2026;1$y",
    },
  },
}
