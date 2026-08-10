local Passes = {}

local Pass = {}
Pass.__index = Pass

function Pass.new(name, order, pipeline, load_op, instances, reads, writes, after)
  return setmetatable({ name = name, order = order, pipeline = pipeline, load_op = load_op, instances = instances, reads = reads, writes = writes, after = after }, Pass)
end

function Pass:encode(renderer, encoder, view, model)
  renderer:encode_semantic_pass(self, encoder, view, model, renderer:resolve_pass_resources(self))
end

function Passes.build(renderer)
  local c = renderer.native.constants
  local background = Pass.new("terminal/background", 10, nil, c.load_clear, function(model)
      return model.columns * model.rows
    end, { "terminal.cells", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, {})
  function background:initialize(owner)
    self.pipeline = owner:create_pipeline("background-pass", "background_vs", "background_fs")
  end
  function background:shutdown(owner)
    if self.pipeline then
      owner:release_native(self.pipeline)
      self.pipeline = nil
    end
  end
  return {
    background,
    Pass.new("terminal/glyph", 20, renderer.glyph_pipeline, c.load_load, function(model)
      return renderer.glyph_count or 0
    end, { "text.shaped_glyphs", "text.alpha_atlas", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/background" }),
    Pass.new("terminal/cursor", 30, renderer.cursor_pipeline, c.load_load, function()
      return 1
    end, { "terminal.cursor", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }, { "terminal/glyph" }),
  }
end

return Passes
