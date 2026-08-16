local Assert = require("tests.assert")
local KittyImages = require("kiwi.renderer.kitty_images")
local Passes = require("kiwi.renderer.passes")
local PassRegistry = require("kiwi.renderer.pass_registry")
local Parser = require("kiwi.terminal.parser")
local Resources = require("kiwi.renderer.resources")
local State = require("kiwi.terminal.state")

return {
  kitty_image_renderer_splits_z_layers_and_preserves_source_rows = function()
    local under, over = KittyImages.plan({
      placements = {
        {
          image_id = 4,
          placement_id = 1,
          column = 2,
          columns = 3,
          row_count = 2,
          rows = { { row = 5, source_row = 0 }, { row = 6, source_row = 1 } },
          visible = true,
          z = -2,
        },
        {
          image_id = 8,
          placement_id = 2,
          column = 8,
          columns = 1,
          row_count = 1,
          rows = { { row = 1, source_row = 0 } },
          visible = true,
          z = 0,
        },
      },
    })
    Assert.equal(#under, 2)
    Assert.equal(#over, 1)
    Assert.equal(under[1].image_id, 4)
    Assert.equal(under[2].source_row, 1)
    Assert.equal(under[2].row_count, 2)
    Assert.equal(over[1].image_id, 8)
  end,
  kitty_image_renderer_uses_the_composition_fixture_as_its_visible_input = function()
    local fixture = require("tests.fixtures.vt.kitty_graphics_composition")
    local state = State.new(fixture.columns, fixture.rows)
    local parser = Parser.new(state)
    parser:feed(fixture.input)
    parser:finish()
    local under, over = KittyImages.plan(state:kitty_placements_view())
    Assert.equal(#under, 1)
    Assert.equal(#over, 1)
    Assert.equal(under[1].placement_id, 1)
    Assert.equal(over[1].placement_id, 2)
  end,
  kitty_image_renderer_releases_offscreen_textures_and_gpu_accounting = function()
    local releases = {}
    local graphics = {
      pending = {},
      take_gpu_releases = function(self)
        local items = self.pending
        self.pending = {}
        return items
      end,
      release_gpu_upload = function(self, id, generation, reason)
        releases[#releases + 1] = { generation = generation, id = id, reason = reason }
        self.pending[#self.pending + 1] = { generation = generation, id = id }
        return true
      end,
    }
    local native_releases = {}
    local owner = {
      release_native = function(_, handle) native_releases[#native_releases + 1] = handle end,
    }
    local images = KittyImages.new(4)
    images.textures[9] = { bind_group = "bind", generation = 3, id = 9, texture = "texture", view = "view" }
    local changed = images:sync(owner, {
      kitty_graphics = graphics,
      kitty_placements_view = function() return { placements = {} } end,
    })
    Assert.equal(changed, true)
    Assert.equal(table.concat(native_releases, ","), "bind,view,texture")
    Assert.equal(releases[1].id, 9)
    Assert.equal(releases[1].generation, 3)
    Assert.equal(images:descriptor().textures, 0)
  end,
  kitty_image_renderer_uploads_only_visible_row_instances = function()
    local writes = {}
    local touches = 0
    local graphics = {
      take_gpu_releases = function() return {} end,
      upload_descriptor = function(_, id)
        return { bytes = 4, generation = 2, height = 1, id = id, pixels = nil, width = 1 }
      end,
      touch_gpu_upload = function()
        touches = touches + 1
        return true
      end,
    }
    local images = KittyImages.new(4)
    images.instance_buffer = "instances"
    images.ensure_texture = function(self, _, _, image)
      local entry = { generation = image.generation, id = image.id }
      self.textures[image.id] = entry
      return entry, true
    end
    local changed = images:sync({
      context = { queue = "queue" },
      native = {
        lib = {
          wgpuQueueWriteBuffer = function(_, buffer, offset, _, bytes)
            writes[#writes + 1] = { buffer = buffer, bytes = bytes, offset = offset }
          end,
        },
      },
    }, {
      columns = 10,
      rows = 5,
      kitty_graphics = graphics,
      kitty_placements_view = function()
        return {
          placements = {
            {
              image_id = 1,
              placement_id = 4,
              column = 0,
              columns = 5,
              row_count = 2,
              rows = { { row = 1, source_row = 0 }, { row = 2, source_row = 1 } },
              visible = true,
              z = -1,
            },
          },
        }
      end,
    })
    Assert.equal(changed, true)
    Assert.equal(#writes, 1)
    Assert.equal(writes[1].buffer, "instances")
    Assert.equal(writes[1].bytes, 64)
    Assert.equal(touches, 2)
    Assert.near(images.instances[0].x, -1, 0.0001)
    Assert.near(images.instances[0].y, 0.6, 0.0001)
    Assert.near(images.instances[1].v0, 0.5, 0.0001)
    Assert.near(images.instances[1].v1, 1, 0.0001)
    local descriptor = images:descriptor()
    Assert.equal(descriptor.placements.count, 1)
    Assert.equal(descriptor.placements.placement_1.first_row, 1)
    Assert.equal(descriptor.placements.placement_1.last_row, 2)
    Assert.equal(descriptor.placements.placement_1.layer, "under")
  end,
  kitty_image_renderer_rewrites_a_resident_texture_for_an_animation_frame = function()
    local images = KittyImages.new(1)
    images.textures[3] = { frame_revision = 1, generation = 4, id = 3, texture = "texture" }
    local uploaded
    images.upload_pixels = function(_, _, texture, image)
      uploaded = { revision = image.frame_revision, texture = texture }
    end
    local entry, changed = images:ensure_texture({}, {}, {
      frame_bytes = 16,
      frame_revision = 2,
      generation = 4,
      id = 3,
    })
    Assert.equal(entry.frame_revision, 2)
    Assert.equal(changed, true)
    Assert.equal(uploaded.texture, "texture")
    Assert.equal(uploaded.revision, 2)
  end,
  kitty_image_renderer_declares_typed_resources_and_stable_composition_order = function()
    local registry = Resources.new(1)
    local handle = registry:register("terminal.kitty_images", {
      kind = "terminal.kitty_images",
      access = "read",
      active = true,
      instances = 3,
    })
    Assert.equal(registry:resolve(handle, "read").descriptor.instances, 3)
    local renderer = {
      native = { constants = { load_clear = 2, load_load = 1 } },
      kitty_images = {
        instances_for = function(_, layer) return layer == "under" and { 1 } or { 1, 2 } end,
      },
    }
    local passes = Passes.build(renderer)
    PassRegistry.validate(passes)
    local names = {}
    for index, pass in ipairs(passes) do names[index] = pass.name end
    Assert.equal(
      table.concat(names, ","),
      "terminal/background,terminal/kitty_images_under,terminal/selection,terminal/search,terminal/glyph,terminal/kitty_images_over,terminal/cursor"
    )
    Assert.equal(passes[2].after[1], "terminal/background")
    Assert.equal(passes[3].after[1], "terminal/kitty_images_under")
    Assert.equal(passes[6].after[1], "terminal/glyph")
    Assert.equal(passes[7].after[1], "terminal/kitty_images_over")
    registry:destroy()
  end,
  kitty_image_pass_resolves_its_typed_resource_before_encoding = function()
    local registry = Resources.new(1)
    local handles = {
      ["terminal.kitty_images"] = registry:register("terminal.kitty_images", { kind = "terminal.kitty_images", access = "read" }),
      ["surface.color"] = registry:register("surface.color", { kind = "surface.color", access = "write" }),
    }
    local captured
    local renderer = {
      native = { constants = { load_clear = 2, load_load = 1 } },
      kitty_images = {
        instances_for = function(_, layer) return layer == "under" and { 1 } or {} end,
      },
      resource_registry = registry,
      resource_handles = handles,
      resolve_pass_resources = require("kiwi.renderer.renderer").resolve_pass_resources,
      encode_kitty_image_pass = function(_, pass, _, _, _, resources)
        captured = { layer = pass.image_layer, resources = resources }
      end,
    }
    local under = Passes.build(renderer)[2]
    under:encode(renderer, nil, nil, {})
    Assert.equal(captured.layer, "under")
    Assert.equal(captured.resources["terminal.kitty_images"].descriptor.access, "read")
    Assert.equal(captured.resources["surface.color"].descriptor.access, "write")
    registry:destroy()
  end,
}
