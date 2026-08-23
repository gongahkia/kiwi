local Passes = {}

local Pass = {}
Pass.__index = Pass

function Pass.new(name, order, pipeline, load_op, instances, reads, writes, after)
  return setmetatable({ name = name, order = order, pipeline = pipeline, load_op = load_op, instances = instances, reads = reads, writes = writes, after = after }, Pass)
end

function Pass:encode(renderer, encoder, view, model)
  renderer:encode_semantic_pass(self, encoder, view, model, self.resources or renderer:resolve_pass_resources(self))
  self.resources = nil
end

function Pass:prepare(renderer)
  self.resources = renderer:resolve_pass_resources(self)
end

local function initialize_pipeline(owner, pass, label, vertex_entry, fragment_entry, shader_path)
  pass.pipeline_label = label
  pass.vertex_entry = vertex_entry
  pass.fragment_entry = fragment_entry
  pass.shader = owner:load_shader(pass.name, pass.name, shader_path)
  pass.pipeline = owner:create_pipeline(label, vertex_entry, fragment_entry, pass.shader, pass.blend, pass.pipeline_layout)
end

local function shutdown_pipeline(owner, pass)
  if pass.pipeline then
    owner:release_native(pass.pipeline)
    pass.pipeline = nil
  end
  if pass.shader then
    pass.shader.release()
    pass.shader = nil
  end
end

function Passes.build(renderer)
  local c = renderer.native.constants
  local background = Pass.new("terminal/background", 10, nil, c.load_clear, function(model)
      return model.columns * model.rows
    end, { "terminal.cells", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, {})
  function background:initialize(owner)
    initialize_pipeline(owner, self, "background-pass", "background_vs", "background_fs")
  end
  function background:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  local images_under
  if renderer.kitty_images then
    images_under = Pass.new("terminal/kitty_images_under", 12, nil, c.load_load, function()
        return #renderer.kitty_images:instances_for("under")
      end, { "terminal.kitty_images" }, { "surface.color" }, { "terminal/background" })
    images_under.blend = "alpha"
    images_under.image_layer = "under"
    function images_under:initialize(owner)
      owner.kitty_images:initialize(owner)
      self.pipeline_layout = owner.kitty_images.pipeline_layout
      initialize_pipeline(owner, self, "kitty-images-under-pass", "kitty_image_vs", "kitty_image_fs", owner.image_shader_path)
    end
    function images_under:encode(owner, encoder, view, model)
      owner:encode_kitty_image_pass(self, encoder, view, model, self.resources or owner:resolve_pass_resources(self))
      self.resources = nil
    end
    function images_under:shutdown(owner)
      shutdown_pipeline(owner, self)
    end
  end
  local selection = Pass.new("terminal/selection", 15, nil, c.load_load, function(model)
      return renderer.selection and renderer.selection.active and model.columns * model.rows or 0
    end, { "terminal.selection", "frame.viewport", "frame.timing" }, { "surface.color" }, images_under and { "terminal/kitty_images_under" } or { "terminal/background" })
  selection.blend = "alpha"
  function selection:initialize(owner)
    initialize_pipeline(owner, self, "selection-pass", "selection_vs", "selection_fs")
  end
  function selection:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  local search = Pass.new("terminal/search", 17, nil, c.load_load, function(model)
      return renderer.search and renderer.search.active and model.columns * model.rows or 0
    end, { "terminal.search", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/selection" })
  search.blend = "alpha"
  function search:initialize(owner)
    initialize_pipeline(owner, self, "search-pass", "search_vs", "search_fs")
  end
  function search:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  local command_regions
  if renderer.command_region_visual_enabled then
    command_regions = Pass.new("terminal/command_regions", 18, nil, c.load_load, function(model)
        return renderer.command_regions and renderer.command_regions.active and model.columns * model.rows or 0
      end, { "terminal.command_regions", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/search" })
    command_regions.blend = "alpha"
    function command_regions:initialize(owner)
      initialize_pipeline(owner, self, "command-region-pass", "command_regions_vs", "command_regions_fs")
    end
    function command_regions:shutdown(owner)
      shutdown_pipeline(owner, self)
    end
  end
  local glyph = Pass.new("terminal/glyph", 20, nil, c.load_load, function(model)
      return renderer.glyph_count or 0
    end, { "text.shaped_glyphs", "text.alpha_atlas", "terminal.hyperlinks", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, command_regions and { "terminal/command_regions" } or { "terminal/search" })
  glyph.blend = "alpha"
  function glyph:initialize(owner)
    initialize_pipeline(owner, self, "glyph-pass", "glyph_vs", "glyph_fs")
  end
  function glyph:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  local images_over
  if renderer.kitty_images then
    images_over = Pass.new("terminal/kitty_images_over", 25, nil, c.load_load, function()
        return #renderer.kitty_images:instances_for("over")
      end, { "terminal.kitty_images" }, { "surface.color" }, { "terminal/glyph" })
    images_over.blend = "alpha"
    images_over.image_layer = "over"
    function images_over:initialize(owner)
      owner.kitty_images:initialize(owner)
      self.pipeline_layout = owner.kitty_images.pipeline_layout
      initialize_pipeline(owner, self, "kitty-images-over-pass", "kitty_image_vs", "kitty_image_fs", owner.image_shader_path)
    end
    function images_over:encode(owner, encoder, view, model)
      owner:encode_kitty_image_pass(self, encoder, view, model, self.resources or owner:resolve_pass_resources(self))
      self.resources = nil
    end
    function images_over:shutdown(owner)
      shutdown_pipeline(owner, self)
      owner.kitty_images:shutdown(owner)
    end
  end
  local cursor = Pass.new("terminal/cursor", 30, nil, c.load_load, function()
      return 1
    end, { "terminal.cursor", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, images_over and { "terminal/kitty_images_over" } or { "terminal/glyph" })
  function cursor:initialize(owner)
    initialize_pipeline(owner, self, "cursor-pass", "cursor_vs", "cursor_fs")
  end
  function cursor:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  local scrollbar = Pass.new("terminal/scrollbar", 35, nil, c.load_load, function()
      return renderer.scrollbar and renderer.scrollbar.active and 1 or 0
    end, { "terminal.scrollbar", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/cursor" })
  scrollbar.blend = "alpha"
  function scrollbar:initialize(owner)
    initialize_pipeline(owner, self, "scrollbar-pass", "scrollbar_vs", "scrollbar_fs")
  end
  function scrollbar:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  local passes = {
    background,
  }
  if images_under then passes[#passes + 1] = images_under end
  passes[#passes + 1] = selection
  passes[#passes + 1] = search
  if command_regions then passes[#passes + 1] = command_regions end
  passes[#passes + 1] = glyph
  if images_over then passes[#passes + 1] = images_over end
  passes[#passes + 1] = cursor
  passes[#passes + 1] = scrollbar
  return passes
end

return Passes
