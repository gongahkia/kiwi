local Passes = {}

local Pass = {}
Pass.__index = Pass

function Pass.new(name, pipeline, load_op, instances, reads, writes)
  return setmetatable({ name = name, pipeline = pipeline, load_op = load_op, instances = instances, reads = reads, writes = writes }, Pass)
end

function Pass:encode(renderer, encoder, view, model)
  renderer:encode_semantic_pass(self, encoder, view, model, renderer:resolve_pass_resources(self))
end

function Passes.build(renderer)
  local c = renderer.native.constants
  return {
    Pass.new("terminal/background", renderer.background_pipeline, c.load_clear, function(model)
      return model.columns * model.rows
    end, { "terminal.cells", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }),
    Pass.new("terminal/glyph", renderer.glyph_pipeline, c.load_load, function(model)
      return renderer.glyph_count or 0
    end, { "text.shaped_glyphs", "text.alpha_atlas", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }),
    Pass.new("terminal/cursor", renderer.cursor_pipeline, c.load_load, function()
      return 1
    end, { "terminal.cursor", "terminal.damage", "frame.viewport", "frame.timing" }, { "surface.color" }),
  }
end

return Passes
