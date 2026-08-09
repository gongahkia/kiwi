return {
  id = "osc-and-strings",
  source = "XTerm Control Sequences: OSC 2 and ST; DCS string termination",
  columns = 4,
  rows = 1,
  input = "\27]2;Kiwi\27\\A\27Pignored\27\\B",
  expected = {
    rows = { "AB  " },
    cursor = { column = 2, row = 0 },
    title = "Kiwi",
    unknown = { dcs = 1 },
  },
}
