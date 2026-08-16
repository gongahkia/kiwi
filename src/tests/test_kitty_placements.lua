local Assert = require("tests.assert")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local escape = string.char(27)
local png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/AAAZ4gk3AAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="

local function frame(controls, data)
  return escape .. "_G" .. controls .. (data and ";" .. data or "") .. escape .. "\\"
end

local function upload(parser, id)
  parser:feed(frame(string.format("a=t,i=%d,s=1,v=1,f=100,t=d,m=0", id), png))
end

local function place(parser, id, placement_id, columns, rows, z)
  parser:feed(frame(string.format("a=p,i=%d,p=%d,c=%d,r=%d,C=1,z=%d", id, placement_id, columns, rows, z or 0)))
end

return {
  kitty_placements_anchor_to_cells_replace_by_pair_and_order_by_z_index = function()
    local state = State.new(5, 3)
    local parser = Parser.new(state)
    upload(parser, 1)
    state:set_cursor(1, 1)
    place(parser, 1, 10, 2, 2, 3)
    place(parser, 1, 11, 1, 1, -2)
    local view = state:kitty_placements_view()
    Assert.equal(#view.placements, 2)
    Assert.equal(view.placements[1].placement_id, 11)
    Assert.equal(view.placements[2].placement_id, 10)
    Assert.equal(view.placements[2].column, 1)
    Assert.equal(view.placements[2].rows[1].row, 1)
    Assert.equal(view.placements[2].rows[2].row, 2)
    Assert.equal(state.cursor.column, 1)
    Assert.equal(state.cursor.row, 1)

    state:set_cursor(0, 0)
    place(parser, 1, 10, 1, 1, 3)
    view = state:kitty_placements_view()
    Assert.equal(#view.placements, 2)
    Assert.equal(view.placements[2].column, 0)
    Assert.equal(#view.placements[2].rows, 1)
    Assert.equal(view.stats.replaced, 1)
    Assert.equal(#state.primary.rows[1].kitty_placement_ids, 1)
    Assert.equal(state.primary.rows[1].kitty_placement_ids[1], view.placements[1].id)

    local responses = state:pop_responses()
    Assert.equal(responses[1], escape .. "_Gi=1,p=10;OK" .. escape .. "\\")
    Assert.equal(responses[2], escape .. "_Gi=1,p=11;OK" .. escape .. "\\")
    Assert.equal(responses[3], escape .. "_Gi=1,p=10;OK" .. escape .. "\\")
  end,
  kitty_placements_follow_scrollback_then_release_after_history_eviction = function()
    local state = State.new(4, 2, { scrollback_limit = 2 })
    local parser = Parser.new(state)
    upload(parser, 2)
    place(parser, 2, 4, 1, 2, 0)
    state:pop_responses()

    state:scroll_up(1)
    local view = state:kitty_placements_view()
    Assert.equal(#view.placements, 1)
    Assert.equal(#view.placements[1].rows, 1)
    Assert.equal(view.placements[1].rows[1].row, 0)
    Assert.equal(view.placements[1].rows[1].source_row, 1)

    state:scroll_history(1)
    view = state:kitty_placements_view()
    Assert.equal(#view.placements[1].rows, 2)
    Assert.equal(view.placements[1].rows[1].source_row, 0)
    Assert.equal(view.placements[1].rows[2].source_row, 1)
    state:scroll_history(-1)

    state:scroll_up(2)
    state:scroll_up(1)
    Assert.equal(#state:kitty_placements_view().placements, 0)
    Assert.truthy(state.kitty_placements:snapshot().stats.released >= 1)
  end,
  kitty_placements_release_primary_anchors_on_reflow_and_keep_alternate_lifecycles_bounded = function()
    local state = State.new(4, 2)
    local parser = Parser.new(state)
    upload(parser, 3)
    state:set_cursor(2, 0)
    place(parser, 3, 1, 2, 2, 0)
    state:pop_responses()
    state:resize(3, 1)
    local view = state:kitty_placements_view()
    Assert.equal(#view.placements, 0)
    Assert.truthy(state.kitty_placements:snapshot().stats.released >= 1)

    state:erase_in_display(2)
    Assert.equal(#state:kitty_placements_view().placements, 0)
    Assert.equal(state.kitty_graphics:view().image_count, 1)

    parser:feed(frame("a=d,d=I,i=3"))
    Assert.equal(state.kitty_graphics:view().image_count, 0)

    upload(parser, 4)
    state:switch_alternate(true, true)
    place(parser, 4, 2, 1, 1, 0)
    state:pop_responses()
    Assert.equal(#state:kitty_placements_view().placements, 1)
    state:switch_alternate(false, true)
    state:switch_alternate(true, true)
    Assert.equal(#state:kitty_placements_view().placements, 0)
  end,
  kitty_placements_report_unknown_images_and_unsupported_policy = function()
    local state = State.new(3, 2)
    local parser = Parser.new(state)
    parser:feed(frame("a=p,i=77,p=1,c=1,r=1,C=1"))
    parser:feed(frame("a=p,i=77,p=2,c=1,r=1"))
    parser:feed(frame("a=d,d=z"))
    local responses = state:pop_responses()
    Assert.equal(responses[1], escape .. "_Gi=77,p=1;ENOENT:unknown-image" .. escape .. "\\")
    Assert.equal(responses[2], escape .. "_Gi=77,p=2;EINVAL:unsupported-cursor-policy" .. escape .. "\\")
    Assert.equal(responses[3], escape .. "_Gi=0;EINVAL:unsupported-delete" .. escape .. "\\")
    Assert.equal(#state:kitty_placements_view().placements, 0)
  end,
  kitty_placements_bound_their_records_and_release_when_the_image_cache_evicts = function()
    local state = State.new(3, 2, {
      kitty_graphics = { max_cpu_bytes = 4, max_decoded_bytes = 4, max_images = 1 },
      kitty_placements = { limit = 1 },
    })
    local parser = Parser.new(state)
    upload(parser, 8)
    place(parser, 8, 1, 1, 1, 0)
    place(parser, 8, 2, 1, 1, 0)
    local responses = state:pop_responses()
    Assert.equal(responses[1], escape .. "_Gi=8,p=1;OK" .. escape .. "\\")
    Assert.equal(responses[2], escape .. "_Gi=8,p=2;EINVAL:placement-limit" .. escape .. "\\")
    Assert.equal(#state:kitty_placements_view().placements, 1)

    upload(parser, 9)
    Assert.equal(#state:kitty_placements_view().placements, 0)
    Assert.equal(state.kitty_graphics:view().images[1].id, 9)
  end,
}
