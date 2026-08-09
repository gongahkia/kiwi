local Passes = {}

local Pass = {}
Pass.__index = Pass

function Pass.new(name, pipeline, load_op, instances)
  return setmetatable({ name = name, pipeline = pipeline, load_op = load_op, instances = instances }, Pass)
end

function Pass:encode(renderer, encoder, view, model)
  renderer:encode_semantic_pass(self, encoder, view, model)
end

function Passes.build(renderer)
  local c = renderer.native.constants
  return {
    Pass.new("terminal/background", renderer.background_pipeline, c.load_clear, function(model)
      return model.columns * model.rows
    end),
    Pass.new("terminal/glyph", renderer.glyph_pipeline, c.load_load, function(model)
      return model.columns * model.rows
    end),
    Pass.new("terminal/cursor", renderer.cursor_pipeline, c.load_load, function()
      return 1
    end),
  }
end

return Passes
