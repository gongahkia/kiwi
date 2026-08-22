return {
  id = "vim-xterm-modes",
  source = "observed Vim startup XTMODKEYS, DECTCEM, and XTWINOPS title-stack controls",
  columns = 1,
  rows = 1,
  input = "\27]0;original\7\27[>4;2m\27[?12h\27[22;2t\27]2;replacement\7\27[22;1t\27]1;icon\7\27[23;2t\27[23;1t\27[?12l\27[>4;0m",
  expected = {
    rows = { " " },
    title = "original",
    modes = { cursor_blink = false, modify_other_keys = 0 },
    unknown = { csi = 0 },
    parser = { errors = 0, ignored = 0 },
  },
}
