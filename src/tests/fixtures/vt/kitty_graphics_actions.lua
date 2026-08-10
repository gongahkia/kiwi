local png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/AAAZ4gk3AAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="

local function frame(controls, payload)
  return "\27_G" .. controls .. (payload and ";" .. payload or "") .. "\27\\"
end

local function transfer(action, id)
  return frame(string.format("a=%s,i=%d,s=1,v=1,f=100,t=d,m=0", action, id), png)
end

return {
  id = "kitty-graphics-actions",
  columns = 4,
  rows = 2,
  input = transfer("t", 1)
    .. transfer("t", 2)
    .. transfer("q", 3)
    .. frame("a=p,i=1,p=1,c=1,r=1,C=1,z=-1")
    .. frame("a=p,i=2,p=2,c=1,r=1,C=1,z=1")
    .. frame("a=d,d=a")
    .. frame("a=p,i=1,p=3,c=1,r=1,C=1")
    .. frame("a=d,d=i,i=1,p=3")
    .. frame("a=p,i=2,p=4,c=1,r=1,C=1")
    .. frame("a=d,d=I,i=2"),
  expected = {
    cursor = { column = 0, row = 0 },
    kitty_graphics = { image_count = 1, image_id = 1 },
    kitty_placements = { count = 0 },
    responses = {
      "\27_Gi=3;OK\27\\",
      "\27_Gi=1,p=1;OK\27\\",
      "\27_Gi=2,p=2;OK\27\\",
      "\27_Gi=1,p=3;OK\27\\",
      "\27_Gi=2,p=4;OK\27\\",
    },
    rows = { "    ", "    " },
  },
}
