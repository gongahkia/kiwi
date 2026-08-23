return {
  id = "kitty-osc21-colours",
  source = "Kitty Color Protocol OSC 21 structured palette/default/cursor query",
  columns = 1,
  rows = 1,
  input = "\27]21;foreground=#010203;1=#0a0c0e;cursor=#070809\27\\\27]21;foreground=?;1=?;cursor=?;selection_background=?\7",
  expected = {
    rows = { " " },
    responses = {
      "\27]21;foreground=rgb:0101/0202/0303;1=rgb:0a0a/0c0c/0e0e;cursor=rgb:0707/0808/0909;selection_background=?\27\\",
    },
    unknown = { osc = 0 },
    parser = { errors = 0, ignored = 0 },
  },
}
