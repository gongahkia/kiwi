return {
  id = "kitty-keyboard",
  source = "Kitty keyboard protocol: query, level-one push/pop, per-screen state, malformed negotiation",
  columns = 5,
  rows = 2,
  input = "\27[?u\27[>1u\27[?u\27[?1049h\27[?u\27[>1u\27[<u\27[?1049l\27[<u\27[=1;4u",
  expected = {
    modes = { keyboard_flags = 0 },
    responses = { "\27[?0u", "\27[?1u", "\27[?0u" },
    unknown = { csi = 1 },
  },
}
