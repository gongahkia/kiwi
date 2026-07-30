return {
  {
    chunks = { "\27[1;32mu", "\27[0m@\27[34mh\27[0m$ \195", "\169\r\nok" },
    config = { columns = 6, rows = 2, scrollback_limit = 2 },
    name = "coloured shell output",
    path = "tests/golden/terminal/coloured_shell_output.txt",
    provenance = "hand-authored shell-style stream",
    purpose = "coloured output, UTF-8 chunking, and carriage-return line feed",
  },
  {
    chunks = { "one\r\ntwo\r\n", "three" },
    config = { columns = 4, rows = 2, scrollback_limit = 2 },
    name = "scrollback shell output",
    path = "tests/golden/terminal/scrollback_shell_output.txt",
    provenance = "hand-authored scrolling stream",
    purpose = "full-screen primary scrolling and bounded scrollback",
  },
  {
    chunks = { "main\27[?1049h", "edit\27[?1049l\27[999z", "\27]0;title\7!" },
    config = { columns = 4, rows = 2, scrollback_limit = 1 },
    name = "alternate restore and unsupported sequences",
    path = "tests/golden/terminal/alternate_restore_and_unsupported.txt",
    provenance = "hand-authored DEC and unsupported-sequence stream",
    purpose = "alternate restoration and safe unsupported reporting",
  },
}
