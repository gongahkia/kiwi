local Assert = require("tests.assert")
local PreparedImages = require("kiwi.renderer.prepared_images")

return {
  prepared_images_exposes_decoded_data_and_visible_rows_without_backend_handles = function()
    local active
    local graphics = {
      set_active_images = function(_, ids) active = ids end,
      upload_descriptor = function(_, id)
        return { bytes = 16, generation = id + 10, id = id, pixels = "pixels", height = 2, width = 2 }
      end,
    }
    local plan = PreparedImages.prepare({
      kitty_graphics = graphics,
      kitty_placements_view = function()
        return {
          placements = {
            {
              image_id = 4,
              placement_id = 8,
              column = 2,
              columns = 3,
              row_count = 2,
              rows = { { row = 1, source_row = 0 }, { row = 2, source_row = 1 } },
              visible = true,
              z = -1,
            },
          },
        }
      end,
    })
    Assert.truthy(plan ~= nil)
    Assert.equal(#plan.under, 2)
    Assert.equal(#plan.over, 0)
    Assert.truthy(active[4])
    Assert.equal(plan.descriptors[4].generation, 14)
    Assert.equal(plan.under[2].source_row, 1)
    Assert.equal(plan.native, nil)
  end,
}
