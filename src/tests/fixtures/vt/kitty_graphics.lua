local png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/AAAZ4gk3AAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="

return {
  id = "kitty-graphics",
  columns = 4,
  rows = 1,
  input = "\27_Ga=t,i=1,s=1,v=1,f=100,t=d,m=0;" .. png .. "\27\\",
  expected = {
    cursor = { column = 0, row = 0 },
    rows = { "    " },
  },
}
