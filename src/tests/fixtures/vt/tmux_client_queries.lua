return {
  id = "tmux-client-queries",
  source = "tmux 3.7b Linux native capture: theme, version, pixel geometry, and application escape-key queries",
  columns = 7,
  rows = 3,
  state_options = { cell_width = 9, cell_height = 17 },
  input = "\27[?2031h\27[?996n\27[>q\27[14t\27[?7727h",
  expected = {
    cursor = { column = 0, row = 0 },
    responses = { "\27[4;51;63t" },
    unknown = { csi = 4 },
  },
}
