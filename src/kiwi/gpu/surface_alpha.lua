-- WGPUCompositeAlphaMode values from the pinned webgpu.h ABI.
local Alpha = {}
function Alpha.select(modes, count, transparent)
  if transparent then
    for _, preferred in ipairs({ 2, 3 }) do
      for index = 0, count - 1 do
        if tonumber(modes[index]) == preferred then return preferred, true end
      end
    end
  end
  for index = 0, count - 1 do
    if tonumber(modes[index]) == 1 then return 1, false end
  end
  return tonumber(modes[0]), false
end
return Alpha
