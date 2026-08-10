local Assert = require("tests.assert")
local Reloader = require("kiwi.renderer.shader_reloader")

local function new_loader(sources, rejected_pass)
  local loader = { sources = sources, reads = 0, compilations = 0, released = {} }
  function loader:read(definition)
    self.reads = self.reads + 1
    local source = self.sources[definition.path]
    if source == nil then error("shader module " .. definition.id .. " could not read source") end
    return source
  end
  function loader:fingerprint(source)
    return source
  end
  function loader:load_source(definition, source)
    self.compilations = self.compilations + 1
    if definition.pass == rejected_pass or source == "invalid" then
      error("shader module " .. definition.id .. " for pass " .. definition.pass .. " from " .. definition.path .. " compilation failed")
    end
    local released = false
    return {
      id = definition.id,
      pass = definition.pass,
      path = definition.path,
      source_fingerprint = source,
      release = function()
        if released then return end
        released = true
        loader.released[#loader.released + 1] = "shader:" .. definition.pass .. ":" .. source
      end,
    }
  end
  return loader
end

local function new_pass(name, source, events, path)
  path = path or "development.wgsl"
  local old_pipeline = { label = "old:" .. name }
  local old_shader = {
    id = name,
    pass = name,
    path = path,
    source_fingerprint = source,
    release = function() events[#events + 1] = "shader-release:" .. name end,
  }
  return {
    name = name,
    pipeline_label = "pipeline:" .. name,
    vertex_entry = "vertex:" .. name,
    fragment_entry = "fragment:" .. name,
    shader = old_shader,
    pipeline = old_pipeline,
  }, old_pipeline, old_shader
end

local function new_owner(events)
  local owner = { events = events }
  function owner:create_pipeline(label, vertex_entry, fragment_entry, shader)
    self.events[#self.events + 1] = "pipeline-create:" .. label
    return {
      label = label,
      vertex_entry = vertex_entry,
      fragment_entry = fragment_entry,
      shader = shader,
    }
  end
  function owner:release_native(pipeline)
    self.events[#self.events + 1] = "pipeline-release:" .. pipeline.label
  end
  return owner
end

return {
  shader_reload_replaces_all_changed_pipelines_after_validation = function()
    local events = {}
    local loader = new_loader({ ["development.wgsl"] = "baseline" })
    local reloader = Reloader.new({ enabled = true, paths = { "development.wgsl" }, loader = loader })
    local background, old_background_pipeline = new_pass("terminal/background", "baseline", events)
    local glyph, old_glyph_pipeline = new_pass("terminal/glyph", "baseline", events)
    local passes = { background, glyph }
    local owner = new_owner(events)
    reloader:track(passes)
    loader.sources["development.wgsl"] = "edited"

    local reloaded, message = reloader:reload(owner, passes, false)

    Assert.equal(reloaded, true)
    Assert.truthy(message:match("applied source development%.wgsl") ~= nil)
    Assert.truthy(background.pipeline ~= old_background_pipeline)
    Assert.truthy(glyph.pipeline ~= old_glyph_pipeline)
    Assert.equal(background.shader.source_fingerprint, "edited")
    Assert.equal(glyph.shader.source_fingerprint, "edited")
    Assert.equal(table.concat(events, ","), "pipeline-create:pipeline:terminal/background,pipeline-create:pipeline:terminal/glyph,pipeline-release:old:terminal/background,shader-release:terminal/background,pipeline-release:old:terminal/glyph,shader-release:terminal/glyph")
  end,
  shader_reload_rejects_a_candidate_batch_without_touching_active_pipelines = function()
    local events = {}
    local loader = new_loader({ ["development.wgsl"] = "baseline" }, "terminal/glyph")
    local reloader = Reloader.new({ enabled = true, paths = { "development.wgsl" }, loader = loader })
    local background, old_background_pipeline, old_background_shader = new_pass("terminal/background", "baseline", events)
    local glyph, old_glyph_pipeline, old_glyph_shader = new_pass("terminal/glyph", "baseline", events)
    local passes = { background, glyph }
    local owner = new_owner(events)
    reloader:track(passes)
    loader.sources["development.wgsl"] = "edited"

    local reloaded, message = reloader:reload(owner, passes, false)

    Assert.equal(reloaded, false)
    Assert.truthy(message:match("rejected source development%.wgsl") ~= nil)
    Assert.truthy(message:match("retained last%-known%-good module/pipeline") ~= nil)
    Assert.equal(background.pipeline, old_background_pipeline)
    Assert.equal(glyph.pipeline, old_glyph_pipeline)
    Assert.equal(background.shader, old_background_shader)
    Assert.equal(glyph.shader, old_glyph_shader)
    Assert.equal(table.concat(events, ","), "pipeline-create:pipeline:terminal/background,pipeline-release:pipeline:terminal/background")
    Assert.equal(table.concat(loader.released, ","), "shader:terminal/background:edited")
    local history = reloader:history()
    Assert.equal(#history, 1)
    Assert.equal(history[1].level, "error")
  end,
  shader_reload_is_disabled_without_explicit_development_mode = function()
    local events = {}
    local loader = new_loader({ ["development.wgsl"] = "edited" })
    local reloader = Reloader.new({ enabled = false, paths = { "development.wgsl" }, loader = loader })
    local pass = new_pass("terminal/background", "baseline", events)
    local owner = new_owner(events)

    local reloaded, message = reloader:reload(owner, { pass }, true)

    Assert.equal(reloaded, false)
    Assert.truthy(message:match("disabled outside explicit development mode") ~= nil)
    Assert.equal(loader.reads, 0)
    Assert.equal(loader.compilations, 0)
    Assert.equal(#events, 0)
  end,
  shader_reload_polls_only_the_configured_development_path = function()
    local events = {}
    local loader = new_loader({ ["development.wgsl"] = "baseline", ["production.wgsl"] = "other" })
    local reloader = Reloader.new({ enabled = true, paths = { "development.wgsl" }, loader = loader, poll_interval = 1 })
    local development = new_pass("terminal/background", "baseline", events)
    local production = new_pass("terminal/extension", "other", events, "production.wgsl")
    local owner = new_owner(events)
    reloader:track({ development, production })
    loader.sources["development.wgsl"] = "edited"

    local reloaded = reloader:poll(owner, { development, production }, 0)
    local skipped = reloader:poll(owner, { development, production }, 0.5)

    Assert.equal(reloaded, true)
    Assert.equal(skipped, nil)
    Assert.equal(loader.reads, 1)
    Assert.equal(development.shader.source_fingerprint, "edited")
    Assert.equal(production.shader.source_fingerprint, "other")
  end,
  shader_reload_ignores_semantic_passes_without_wgsl_pipelines = function()
    local events = {}
    local loader = new_loader({ ["development.wgsl"] = "baseline" })
    local reloader = Reloader.new({ enabled = true, paths = { "development.wgsl" }, loader = loader })
    local development = new_pass("terminal/background", "baseline", events)
    local observer = { name = "extension/example/frame_observer" }
    local owner = new_owner(events)
    reloader:track({ development, observer })
    loader.sources["development.wgsl"] = "edited"

    local reloaded = reloader:reload(owner, { development, observer }, false)

    Assert.equal(reloaded, true)
    Assert.equal(development.shader.source_fingerprint, "edited")
  end,
}
