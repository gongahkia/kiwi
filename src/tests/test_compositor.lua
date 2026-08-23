local Assert = require("tests.assert")
local Compositor = require("kiwi.renderer.compositor")

return {
  compositor_converts_cell_layouts_to_exact_physical_viewports = function()
    local viewport = Compositor.viewport({ x = 3, y = 5, width = 40, height = 20 }, 9, 18)
    Assert.equal(viewport.x, 27)
    Assert.equal(viewport.y, 90)
    Assert.equal(viewport.width, 360)
    Assert.equal(viewport.height, 360)
  end,
  compositor_requires_each_pane_viewport_to_fit_the_shared_surface = function()
    local compositor = Compositor.new({
      abort_presentation_frame = function() end,
      begin_presentation_frame = function() return {} end,
      present_presentation_frame = function() return true end,
      window = {},
      width = 100,
      height = 80,
    })
    local renderer = {
      encode_into = function() end,
      finish_frame = function() end,
    }
    compositor:validate({ { renderer = renderer, model = {}, viewport = { x = 0, y = 0, width = 100, height = 80 } } })
    local ok = pcall(function()
      compositor:validate({ { renderer = renderer, model = {}, viewport = { x = 60, y = 0, width = 41, height = 80 } } })
    end)
    Assert.truthy(not ok)
  end,
  compositor_tracks_the_earliest_pane_animation_and_synchronized_output = function()
    local frame = {}
    local compositor = Compositor.new({
      abort_presentation_frame = function() end,
      begin_presentation_frame = function() return frame end,
      present_presentation_frame = function() return true end,
      window = { minimized = false },
      width = 100,
      height = 80,
    })
    local entries = {
      { model = { modes = {} }, renderer = { needs_render = function(_, now) return now >= 3 end, next_render_deadline = function() return 3 end } },
      { model = { modes = {} }, renderer = { needs_render = function(_, now) return now >= 2 end, next_render_deadline = function() return 2 end } },
    }
    Assert.equal(compositor:next_render_deadline(entries), 2)
    Assert.truthy(not compositor:needs_render(entries, 1))
    Assert.truthy(compositor:needs_render(entries, 2))
    Assert.truthy(compositor:can_present(entries))
    entries[2].model.modes.synchronized_output = true
    Assert.truthy(not compositor:can_present(entries))
  end,
  compositor_uses_an_opaque_presentation_frame_lifecycle = function()
    local events = {}
    local frame = { kind = "test-presentation" }
    local compositor = Compositor.new({
      abort_presentation_frame = function(_, value)
        Assert.equal(value, frame)
        events[#events + 1] = "abort"
      end,
      begin_presentation_frame = function()
        events[#events + 1] = "begin"
        return frame
      end,
      present_presentation_frame = function(_, value)
        Assert.equal(value, frame)
        events[#events + 1] = "present"
        return true
      end,
      window = { minimized = false },
      width = 100,
      height = 80,
    })
    local renderer = {
      encode_into = function(_, value, model, time, dirty, boundaries, options)
        Assert.equal(value, frame)
        Assert.equal(model.id, "pane")
        Assert.equal(time, 4)
        Assert.truthy(dirty)
        Assert.truthy(boundaries)
        Assert.truthy(options.clear)
        events[#events + 1] = "encode"
      end,
      finish_frame = function(_, model, time)
        Assert.equal(model.id, "pane")
        Assert.equal(time, 4)
        events[#events + 1] = "finish"
      end,
    }
    Assert.truthy(compositor:render({ { model = { id = "pane" }, renderer = renderer, viewport = { x = 0, y = 0, width = 100, height = 80 } } }, 4, true, true))
    Assert.equal(table.concat(events, ","), "begin,encode,present,finish")
  end,
  compositor_maps_framebuffer_capture_only_after_submission = function()
    local events = {}
    local frame = { encoder = {}, texture = {} }
    local compositor = Compositor.new({
      abort_presentation_frame = function() events[#events + 1] = "abort" end,
      begin_framebuffer_capture = function(_, number)
        Assert.equal(number, 1)
        events[#events + 1] = "capture-begin"
        return true
      end,
      begin_presentation_frame = function()
        events[#events + 1] = "begin"
        return frame
      end,
      encode_framebuffer_capture = function(_, encoder, texture)
        Assert.equal(encoder, frame.encoder)
        Assert.equal(texture, frame.texture)
        events[#events + 1] = "capture-encode"
      end,
      poll_framebuffer_capture = function() events[#events + 1] = "capture-poll" end,
      present_presentation_frame = function()
        events[#events + 1] = "present"
        return true
      end,
      submit_framebuffer_capture = function() events[#events + 1] = "capture-submit" end,
      window = { minimized = false },
      width = 100,
      height = 80,
    })
    local renderer = {
      encode_into = function() events[#events + 1] = "encode" end,
      finish_frame = function() events[#events + 1] = "finish" end,
    }
    Assert.truthy(compositor:render({ { model = {}, renderer = renderer, viewport = { x = 0, y = 0, width = 100, height = 80 } } }, 1))
    Assert.equal(table.concat(events, ","), "begin,encode,capture-begin,capture-encode,present,capture-submit,finish,capture-poll")
  end,
  compositor_aborts_an_acquired_presentation_frame_when_encoding_fails = function()
    local frame = {}
    local aborted = 0
    local compositor = Compositor.new({
      abort_presentation_frame = function(_, value)
        Assert.equal(value, frame)
        aborted = aborted + 1
      end,
      begin_presentation_frame = function() return frame end,
      present_presentation_frame = function() error("unexpected presentation") end,
      window = { minimized = false },
      width = 100,
      height = 80,
    })
    local ok = pcall(function()
      compositor:render({ { model = {}, renderer = {
        encode_into = function() error("expected encoder failure") end,
        finish_frame = function() error("unexpected finish") end,
      }, viewport = { x = 0, y = 0, width = 100, height = 80 } } }, 1)
    end)
    Assert.truthy(not ok)
    Assert.equal(aborted, 1)
  end,
  compositor_aborts_an_unsubmitted_framebuffer_capture_when_capture_encoding_fails = function()
    local frame = { encoder = {}, texture = {} }
    local capture_aborted = 0
    local presentation_aborted = 0
    local compositor = Compositor.new({
      abort_framebuffer_capture = function() capture_aborted = capture_aborted + 1 end,
      abort_presentation_frame = function() presentation_aborted = presentation_aborted + 1 end,
      begin_framebuffer_capture = function() return true end,
      begin_presentation_frame = function() return frame end,
      encode_framebuffer_capture = function() error("expected capture encoding failure") end,
      present_presentation_frame = function() error("unexpected presentation") end,
      window = { minimized = false },
      width = 100,
      height = 80,
    })
    local ok = pcall(function()
      compositor:render({ { model = {}, renderer = {
        encode_into = function() end,
        finish_frame = function() error("unexpected finish") end,
      }, viewport = { x = 0, y = 0, width = 100, height = 80 } } }, 1)
    end)
    Assert.truthy(not ok)
    Assert.equal(capture_aborted, 1)
    Assert.equal(presentation_aborted, 1)
  end,
}
