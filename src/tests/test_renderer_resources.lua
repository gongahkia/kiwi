local Assert = require("tests.assert")
local ffi = require("ffi")
local Passes = require("kiwi.renderer.passes")
local Renderer = require("kiwi.renderer.renderer")
local Resources = require("kiwi.renderer.resources")

local function cells_descriptor(columns)
  return {
    kind = "terminal.cells",
    access = "read",
    columns = columns,
    rows = 24,
    capacity = columns * 24,
    instance_bytes = 40,
  }
end

local function expect_error(callback)
  local ok, message = pcall(callback)
  Assert.equal(ok, false)
  Assert.truthy(tostring(message):match("render resource registry") ~= nil)
end

local function descriptor_for(name)
  return { kind = name, access = name == "surface.color" and "write" or "read" }
end

return {
  renderer_resources_resolve_cloned_semantic_descriptors = function()
    local registry = Resources.new(3)
    local handle = registry:register("terminal.cells", cells_descriptor(80))
    local resource = registry:resolve(handle, "read")
    Assert.equal(resource.name, "terminal.cells")
    Assert.equal(resource.generation, 3)
    Assert.equal(resource.descriptor.columns, 80)
    resource.descriptor.columns = 1
    Assert.equal(registry:resolve(handle).descriptor.columns, 80)
    expect_error(function() registry:resolve(handle, "write") end)
  end,
  renderer_resources_reject_raw_or_unknown_descriptors = function()
    local registry = Resources.new(1)
    expect_error(function()
      registry:register("terminal.cells", {
        kind = "terminal.cells",
        access = "read",
        native = function() end,
      })
    end)
    expect_error(function()
      registry:register("terminal.cells", {
        kind = "terminal.cells",
        access = "read",
        native = ffi.new("uint32_t[1]"),
      })
    end)
    expect_error(function()
      registry:register("terminal.unknown", { kind = "terminal.unknown", access = "read" })
    end)
    expect_error(function()
      registry:register("surface.color", { kind = "surface.color", access = "read" })
    end)
  end,
  renderer_resources_reject_stale_renderer_generations = function()
    local previous = Resources.new(7)
    local previous_handle = previous:register("terminal.cells", cells_descriptor(80))
    local current = Resources.new(8)
    current:register("terminal.cells", cells_descriptor(120))
    expect_error(function() current:resolve(previous_handle) end)
    previous:destroy()
    expect_error(function() previous:resolve(previous_handle) end)
  end,
  renderer_resources_release_owned_native_resources_once_in_reverse_order = function()
    local registry = Resources.new(1)
    local events = {}
    local first = {}
    local second = {}
    registry:own_native("first", first, function() events[#events + 1] = "first-release" end, function() events[#events + 1] = "first-destroy" end)
    registry:own_native("second", second, function() events[#events + 1] = "second-release" end, function() events[#events + 1] = "second-destroy" end)
    expect_error(function() registry:own_native("duplicate", first, function() end) end)
    registry:destroy()
    registry:destroy()
    Assert.equal(table.concat(events, ","), "second-destroy,second-release,first-destroy,first-release")
  end,
  renderer_resources_allow_pass_owned_release_before_registry_teardown = function()
    local registry = Resources.new(1)
    local events = {}
    local handle = {}
    registry:own_native("pipeline", handle, function() events[#events + 1] = "release" end)
    registry:release_native(handle)
    registry:destroy()
    Assert.equal(table.concat(events, ","), "release")
  end,
  built_in_passes_resolve_typed_resources_before_encoding = function()
    local registry = Resources.new(1)
    local handles = {}
    for _, name in ipairs({
      "terminal.cells",
      "text.shaped_glyphs",
      "terminal.cursor",
      "terminal.selection",
      "terminal.search",
      "terminal.hyperlinks",
      "terminal.damage",
      "frame.viewport",
      "frame.timing",
      "text.alpha_atlas",
      "surface.color",
    }) do
      handles[name] = registry:register(name, descriptor_for(name))
    end
    local captured
    local renderer = {
      native = { constants = { load_clear = 2, load_load = 1 } },
      glyph_count = 4,
      resource_registry = registry,
      resource_handles = handles,
      resolve_pass_resources = Renderer.resolve_pass_resources,
      encode_semantic_pass = function(_, _, _, _, _, resources)
        captured = resources
      end,
    }
    local passes = Passes.build(renderer)
    passes[4]:encode(renderer, nil, nil, { columns = 80, rows = 24 })
    Assert.equal(captured["text.shaped_glyphs"].name, "text.shaped_glyphs")
    Assert.equal(captured["terminal.hyperlinks"].descriptor.access, "read")
    Assert.equal(captured["text.alpha_atlas"].descriptor.access, "read")
    Assert.equal(captured["surface.color"].descriptor.access, "write")
  end,
  background_pass_owns_pipeline_through_its_lifecycle = function()
    local events = {}
    local renderer = {
      native = { constants = { load_clear = 2, load_load = 1 } },
      glyph_pipeline = {},
      cursor_pipeline = {},
      load_shader = function()
        return { handle = {}, release = function() end }
      end,
      create_pipeline = function(_, label, vertex, fragment)
        events[#events + 1] = label .. ":" .. vertex .. ":" .. fragment
        return {}
      end,
      release_native = function(_, pipeline)
        Assert.truthy(pipeline ~= nil)
        events[#events + 1] = "background-release"
      end,
    }
    local background = Passes.build(renderer)[1]
    background:initialize(renderer)
    Assert.truthy(background.pipeline ~= nil)
    background:shutdown(renderer)
    Assert.equal(background.pipeline, nil)
    Assert.equal(table.concat(events, ","), "background-pass:background_vs:background_fs,background-release")
  end,
  glyph_pass_owns_pipeline_through_its_lifecycle = function()
    local events = {}
    local renderer = {
      native = { constants = { load_clear = 2, load_load = 1 } },
      cursor_pipeline = {},
      glyph_count = 4,
      load_shader = function()
        return { handle = {}, release = function() end }
      end,
      create_pipeline = function(_, label, vertex, fragment)
        events[#events + 1] = label .. ":" .. vertex .. ":" .. fragment
        return {}
      end,
      release_native = function(_, pipeline)
        Assert.truthy(pipeline ~= nil)
        events[#events + 1] = "glyph-release"
      end,
    }
    local glyph = Passes.build(renderer)[4]
    glyph:initialize(renderer)
    Assert.truthy(glyph.pipeline ~= nil)
    glyph:shutdown(renderer)
    Assert.equal(glyph.pipeline, nil)
    Assert.equal(table.concat(events, ","), "glyph-pass:glyph_vs:glyph_fs,glyph-release")
  end,
  cursor_pass_owns_pipeline_through_its_lifecycle = function()
    local events = {}
    local renderer = {
      native = { constants = { load_clear = 2, load_load = 1 } },
      glyph_count = 4,
      load_shader = function()
        return { handle = {}, release = function() end }
      end,
      create_pipeline = function(_, label, vertex, fragment)
        events[#events + 1] = label .. ":" .. vertex .. ":" .. fragment
        return {}
      end,
      release_native = function(_, pipeline)
        Assert.truthy(pipeline ~= nil)
        events[#events + 1] = "cursor-release"
      end,
    }
    local cursor = Passes.build(renderer)[5]
    cursor:initialize(renderer)
    Assert.truthy(cursor.pipeline ~= nil)
    cursor:shutdown(renderer)
    Assert.equal(cursor.pipeline, nil)
    Assert.equal(table.concat(events, ","), "cursor-pass:cursor_vs:cursor_fs,cursor-release")
  end,
  built_in_passes_load_stable_pass_owned_shader_modules = function()
    local modules = {}
    local renderer = {
      native = { constants = { load_clear = 2, load_load = 1 } },
      glyph_count = 4,
      load_shader = function(_, id, pass)
        modules[#modules + 1] = id .. ":" .. pass
        return { id = id, pass = pass, handle = {}, release = function() end }
      end,
      create_pipeline = function() return {} end,
      release_native = function() end,
    }
    local passes = Passes.build(renderer)
    for _, pass in ipairs(passes) do pass:initialize(renderer) end
    Assert.equal(table.concat(modules, ","), "terminal/background:terminal/background,terminal/selection:terminal/selection,terminal/search:terminal/search,terminal/glyph:terminal/glyph,terminal/cursor:terminal/cursor")
    for index = #passes, 1, -1 do passes[index]:shutdown(renderer) end
  end,
}
