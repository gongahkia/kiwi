local png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/AAAZ4gk3AAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="

return {
  id = "kitty-placements",
  columns = 4,
  rows = 2,
  input = "\27_Ga=t,i=1,s=1,v=1,f=100,t=d,m=0;" .. png .. "\27\\"
    .. "\27_Ga=p,i=1,p=5,c=2,r=1,C=1,z=-1\27\\",
  expected = {
    cursor = { column = 0, row = 0 },
    kitty_placements = { columns = 2, image_id = 1, placement_id = 5, z = -1 },
    rows = { "    ", "    " },
  },
}
