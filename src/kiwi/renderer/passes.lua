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

local function initialize_pipeline(owner, pass, label, vertex_entry, fragment_entry)
  pass.pipeline_label = label
  pass.vertex_entry = vertex_entry
  pass.fragment_entry = fragment_entry
  pass.shader = owner:load_shader(pass.name, pass.name)
  pass.pipeline = owner:create_pipeline(label, vertex_entry, fragment_entry, pass.shader, pass.blend)
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
  local selection = Pass.new("terminal/selection", 15, nil, c.load_load, function(model)
      return renderer.selection and renderer.selection.active and model.columns * model.rows or 0
    end, { "terminal.selection", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/background" })
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
  local glyph = Pass.new("terminal/glyph", 20, nil, c.load_load, function(model)
      return renderer.glyph_count or 0
    end, { "text.shaped_glyphs", "text.alpha_atlas", "terminal.hyperlinks", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/search" })
  function glyph:initialize(owner)
    initialize_pipeline(owner, self, "glyph-pass", "glyph_vs", "glyph_fs")
  end
  function glyph:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  local cursor = Pass.new("terminal/cursor", 30, nil, c.load_load, function()
      return 1
    end, { "terminal.cursor", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/glyph" })
  function cursor:initialize(owner)
    initialize_pipeline(owner, self, "cursor-pass", "cursor_vs", "cursor_fs")
  end
  function cursor:shutdown(owner)
    shutdown_pipeline(owner, self)
  end
  return {
    background,
    selection,
    search,
    glyph,
    cursor,
  }
end

return Passes
