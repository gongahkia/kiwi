return {
  id = "pointer-shape",
  source = "Ghostty, Kitty, and foot OSC 22 CSS cursor-name convention",
  columns = 1,
  rows = 1,
  input = "\27]22;pointer\7",
  expected = {
    rows = { " " },
    pointer_shape = "pointer",
    unknown = { osc = 0 },
    parser = { errors = 0, ignored = 0 },
  },
}
