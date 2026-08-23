local Assert = require("tests.assert")
local Consumer = require("kiwi.renderer.gtk_gl_consumer")
local State = require("kiwi.terminal.state")
local System = require("kiwi.font.system")

local function font_system()
  return System.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
end

return {
  gtk_gl_consumer_commits_terminal_damage_only_after_native_snapshot_acceptance = function()
    local snapshots = {}
    local window = {
      enable_gl_area_probe = function() return true end,
      submit_gl_area_snapshot = function(_, snapshot)
        snapshots[#snapshots + 1] = snapshot
        return true
      end,
    }
    local font = font_system()
    local state = State.new(8, 2)
    state:write_codepoint("K")
    local consumer = Consumer.new(window, font, state)
    Assert.truthy(consumer:needs_render(0))
    Assert.truthy(consumer:render(state, 1, false, false))
    Assert.equal(#snapshots, 1)
    Assert.equal(snapshots[1].revision, 2)
    Assert.equal(snapshots[1].cell_count, 16)
    Assert.equal(#snapshots[1].cell_updates, 1)
    Assert.equal(snapshots[1].cell_updates[1].first, 0)
    Assert.equal(snapshots[1].cell_updates[1].cell_count, 16)
    Assert.equal(snapshots[1].resource_flags, 7)
    Assert.truthy(snapshots[1].glyph_count > 0)
    Assert.truthy(snapshots[1].atlas_bytes > 0)
    Assert.equal(state.damage.dirty_count, 0)
    Assert.truthy(not consumer:needs_render(1))
    Assert.near(consumer:next_render_deadline(), 1.5, 0.00001)
    consumer:destroy()
    font:destroy()
  end,
  gtk_gl_consumer_retains_damage_and_retries_a_rejected_snapshot_as_a_full_grid = function()
    local attempts = {}
    local window = {
      enable_gl_area_probe = function() return true end,
      submit_gl_area_snapshot = function(_, snapshot)
        attempts[#attempts + 1] = snapshot
        return #attempts > 1, "native-rejected"
      end,
    }
    local font = font_system()
    local state = State.new(8, 2)
    local consumer = Consumer.new(window, font, state)
    local submitted, reason = consumer:render(state, 1, false, false)
    Assert.equal(submitted, false)
    Assert.equal(reason, "native-rejected")
    Assert.truthy(state.damage.dirty_count > 0)
    Assert.truthy(consumer:render(state, 2, false, false))
    Assert.equal(attempts[1].cell_count, 16)
    Assert.equal(attempts[2].cell_count, 16)
    Assert.equal(attempts[2].resource_flags, 7)
    Assert.equal(attempts[2].revision, 2)
    Assert.equal(state.damage.dirty_count, 0)
    consumer:destroy()
    font:destroy()
  end,
  gtk_gl_consumer_defers_submission_while_synchronized_output_is_active = function()
    local submissions = 0
    local window = {
      enable_gl_area_probe = function() return true end,
      submit_gl_area_snapshot = function() submissions = submissions + 1; return true end,
    }
    local font = font_system()
    local state = State.new(8, 2)
    state.modes.synchronized_output = true
    local consumer = Consumer.new(window, font, state)
    local submitted, reason = consumer:render(state, 1, false, false)
    Assert.equal(submitted, false)
    Assert.equal(reason, "synchronized-output")
    Assert.equal(submissions, 0)
    Assert.truthy(state.damage.dirty_count > 0)
    consumer:destroy()
    font:destroy()
  end,
  gtk_gl_consumer_resumes_with_a_monotonic_revision_after_a_resize_rebuild = function()
    local snapshot
    local window = {
      enable_gl_area_probe = function() return true end,
      submit_gl_area_snapshot = function(_, value) snapshot = value; return true end,
    }
    local font = font_system()
    local state = State.new(8, 2)
    local consumer = Consumer.new(window, font, state, { next_revision = 17 })
    Assert.truthy(consumer:render(state, 1, false, false))
    Assert.equal(snapshot.revision, 17)
    Assert.equal(consumer.revision, 18)
    consumer:destroy()
    font:destroy()
  end,
  gtk_gl_consumer_submits_only_terminal_damage_after_its_initial_grid = function()
    local snapshots = {}
    local window = {
      enable_gl_area_probe = function() return true end,
      submit_gl_area_snapshot = function(_, snapshot)
        snapshots[#snapshots + 1] = snapshot
        return true
      end,
    }
    local font = font_system()
    local state = State.new(8, 2)
    local consumer = Consumer.new(window, font, state)
    Assert.truthy(consumer:render(state, 1, false, false))
    state:write_codepoint("K")
    Assert.truthy(consumer:render(state, 2, false, false))
    Assert.equal(#snapshots, 2)
    Assert.truthy(snapshots[2].cell_updates[1].cell_count < snapshots[2].cell_count)
    Assert.equal(snapshots[2].resource_flags % 2, 0)
    consumer:destroy()
    font:destroy()
  end,
}
