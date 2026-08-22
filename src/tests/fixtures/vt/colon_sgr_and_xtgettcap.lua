return {
  id = "colon-sgr-and-xtgettcap",
  source = "ECMA-48 colon SGR form and xterm XTGETTCAP query/reply contract",
  columns = 2,
  rows = 1,
  input = "\27[4:3mU\27[4:0mN\27P+q436f;544e;524742\27\\\27P+q5463\27\\",
  expected = {
    rows = { "UN" },
    cursor = { column = 1, row = 0, pending_wrap = true },
    cells = {
      { column = 0, row = 0, flags = 32 },
      { column = 1, row = 0, flags = 0 },
    },
    responses = {
      "\27P1+r436f=323536;544e=787465726d2d6b697769;524742=38\27\\",
      "\27P0+r\27\\",
    },
  },
}
