return {
  id = "osc8-hyperlinks",
  source = "iTerm2 Hyperlinks in Terminal Emulators: OSC 8 open, close, and id reuse",
  columns = 5,
  rows = 1,
  input = "\27]8;id=docs;https://example.test/docs\27\\AB\27]8;;\7C\27]8;id=docs;https://example.test/docs\7D",
  expected = {
    rows = { "ABCD " },
    cursor = { column = 4, row = 0 },
    cells = {
      { column = 0, row = 0, hyperlink_uri = "https://example.test/docs" },
      { column = 1, row = 0, hyperlink_uri = "https://example.test/docs" },
      { column = 2, row = 0, no_hyperlink = true },
      { column = 3, row = 0, hyperlink_uri = "https://example.test/docs" },
    },
  },
}
