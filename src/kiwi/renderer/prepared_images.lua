-- Renderer-neutral selection of decoded Kitty image data and visible rows.
-- Texture residency, upload, and release remain backend responsibilities.
local PreparedImages = {}

local function integer(value, minimum)
  return type(value) == "number" and value % 1 == 0 and value >= minimum
end

local function append_instances(target, placement)
  if not integer(placement.image_id, 1) or not integer(placement.placement_id, 1)
    or not integer(placement.column, 0) or not integer(placement.columns, 1)
    or not integer(placement.row_count, 1) then
    return
  end
  for _, row in ipairs(placement.rows or {}) do
    if integer(row.row, 0) and integer(row.source_row, 0) and row.source_row < placement.row_count then
      target[#target + 1] = {
        column = placement.column,
        columns = placement.columns,
        image_id = placement.image_id,
        placement_id = placement.placement_id,
        row = row.row,
        row_count = placement.row_count,
        source_row = row.source_row,
        z = placement.z or 0,
      }
    end
  end
end

function PreparedImages.plan(view)
  local under = {}
  local over = {}
  for _, placement in ipairs(view and view.placements or {}) do
    if placement.visible then
      append_instances((placement.z or 0) < 0 and under or over, placement)
    end
  end
  return under, over
end

function PreparedImages.prepare(model)
  local graphics = model.kitty_graphics
  if graphics == nil or type(model.kitty_placements_view) ~= "function" then return nil end
  local placement_view = model:kitty_placements_view()
  local under, over = PreparedImages.plan(placement_view)
  local wanted = {}
  local wanted_ids = {}
  for _, layer in ipairs({ under, over }) do
    for _, item in ipairs(layer) do
      if not wanted[item.image_id] then
        wanted[item.image_id] = true
        wanted_ids[#wanted_ids + 1] = item.image_id
      end
    end
  end
  if type(graphics.set_active_images) == "function" then graphics:set_active_images(wanted) end
  local descriptors = {}
  for _, id in ipairs(wanted_ids) do
    local image = graphics:upload_descriptor(id)
    if image then descriptors[id] = image end
  end
  return {
    columns = model.columns,
    descriptors = descriptors,
    graphics = graphics,
    over = over,
    placement_view = placement_view,
    releases = type(graphics.take_gpu_releases) == "function" and graphics:take_gpu_releases() or {},
    rows = model.rows,
    under = under,
    wanted = wanted,
    wanted_ids = wanted_ids,
  }
end

return PreparedImages
