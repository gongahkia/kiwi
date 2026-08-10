local Assert = require("tests.assert")
local Base64 = require("kiwi.terminal.base64")
local KittyGraphics = require("kiwi.terminal.kitty_graphics")
local Parser = require("kiwi.terminal.parser")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

local png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQMAAAAl21bKAAAAA1BMVEX/AAAZ4gk3AAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="

local function transfer(id, data, more)
  return string.format("a=t,i=%d,s=1,v=1,f=100,t=d,m=%d;%s", id, more or 0, data)
end

local function frame(payload)
  return "\27_G" .. payload .. "\27\\"
end

local function apply(cache, id)
  local result = cache:apply(transfer(id, png))
  Assert.truthy(result.ok, result.reason)
end

local function snapshot_with_chunks(input, chunks)
  local state = State.new(4, 1)
  local parser = Parser.new(state)
  local offset = 1
  for _, count in ipairs(chunks) do
    parser:feed(input:sub(offset, offset + count - 1))
    offset = offset + count
  end
  if offset <= #input then parser:feed(input:sub(offset)) end
  parser:finish()
  return Snapshot.encode(state)
end

return {
  kitty_graphics_decodes_a_real_bounded_png_without_mutating_text = function()
    local state = State.new(4, 1)
    local parser = Parser.new(state)
    parser:feed("A" .. frame(transfer(7, png)) .. "B")
    parser:finish()

    Assert.equal(state:get(0, 0).glyph, "A")
    Assert.equal(state:get(1, 0).glyph, "B")
    local view = state.kitty_graphics:view()
    Assert.equal(view.image_count, 1)
    Assert.equal(view.images[1].id, 7)
    Assert.equal(view.images[1].width, 1)
    Assert.equal(view.images[1].height, 1)
    Assert.equal(view.images[1].bytes, 4)
    Assert.equal(view.images[1].gpu, "unallocated")
    Assert.equal(view.stats.decoded, 1)

    local snapshot = Snapshot.encode(state)
    Assert.equal(snapshot:find(png, 1, true), nil)
    Assert.equal(Snapshot.value(state).kitty_graphics.images[1].pixels, nil)
  end,
  kitty_graphics_transfer_is_chunk_boundary_invariant = function()
    local input = frame(transfer(1, png))
    local whole = snapshot_with_chunks(input, { #input })
    for split = 1, #input - 1 do
      Assert.equal(snapshot_with_chunks(input, { split, #input - split }), whole, "split " .. split)
    end
  end,
  kitty_graphics_accumulates_continuations_before_decode = function()
    local cache = KittyGraphics.new()
    local split = 23
    Assert.truthy(cache:apply(transfer(4, png:sub(1, split), 1)).ok)
    Assert.equal(cache:view().image_count, 0)
    Assert.truthy(cache:apply("m=0;" .. png:sub(split + 1)).ok)
    local view = cache:view()
    Assert.equal(view.image_count, 1)
    Assert.equal(view.images[1].id, 4)
    Assert.equal(view.stats.transfers_completed, 1)
  end,
  kitty_graphics_rejects_malformed_and_over_limit_payloads_before_cache_mutation = function()
    local cache = KittyGraphics.new({ max_encoded_bytes = 8 })
    local oversized = cache:apply(transfer(1, png))
    Assert.equal(oversized.ok, false)
    Assert.equal(oversized.reason, "encoded-limit")
    Assert.equal(cache:view().image_count, 0)

    local malformed = KittyGraphics.new()
    local result = malformed:apply(transfer(2, "!!!!"))
    Assert.equal(result.ok, false)
    Assert.equal(result.reason, "invalid-base64")
    Assert.equal(malformed:view().image_count, 0)

    local corrupt_bytes = Base64.decode(png)
    corrupt_bytes = corrupt_bytes:sub(1, 56) .. string.char(0) .. corrupt_bytes:sub(58)
    result = malformed:apply(transfer(2, Base64.encode(corrupt_bytes)))
    Assert.equal(result.ok, false)
    Assert.equal(result.reason, "png-decode")
    Assert.equal(malformed:view().image_count, 0)

    local dimensions = malformed:apply("a=t,i=2,s=9000,v=1,f=100,t=d,m=0;" .. png)
    Assert.equal(dimensions.ok, false)
    Assert.equal(dimensions.reason, "invalid-dimensions")
    Assert.equal(malformed:view().image_count, 0)

    local chunked = KittyGraphics.new({ max_transfer_chunks = 1 })
    Assert.truthy(chunked:apply(transfer(3, "AAAA", 1)).ok)
    result = chunked:apply("m=0;AAAA")
    Assert.equal(result.ok, false)
    Assert.equal(result.reason, "chunk-limit")
    Assert.equal(chunked:view().transfer_open, false)
  end,
  kitty_graphics_evicts_and_releases_cpu_and_gpu_entries_deterministically = function()
    local cache = KittyGraphics.new({
      max_cpu_bytes = 8,
      max_decoded_bytes = 4,
      max_gpu_bytes = 4,
      max_images = 2,
    })
    apply(cache, 1)
    apply(cache, 2)
    local first = assert(cache:upload_descriptor(1))
    Assert.truthy(cache:register_gpu_upload(first.id, first.generation, first.bytes))
    local second = assert(cache:upload_descriptor(2))
    Assert.truthy(cache:register_gpu_upload(second.id, second.generation, second.bytes))
    local releases = cache:take_gpu_releases()
    Assert.equal(#releases, 1)
    Assert.equal(releases[1].id, 1)
    Assert.equal(releases[1].reason, "gpu-evicted")

    apply(cache, 3)
    local view = cache:view()
    Assert.equal(view.image_count, 2)
    Assert.equal(view.images[1].id, 2)
    Assert.equal(view.images[2].id, 3)
    Assert.equal(view.stats.evicted, 1)
    Assert.equal(view.stats.cpu_bytes, 8)

    cache:clear()
    view = cache:view()
    Assert.equal(view.image_count, 0)
    Assert.equal(view.stats.cpu_bytes, 0)
    Assert.equal(view.stats.gpu_bytes, 0)
    releases = cache:take_gpu_releases()
    Assert.equal(#releases, 1)
    Assert.equal(releases[1].id, 2)
    Assert.equal(releases[1].reason, "reset")
  end,
  kitty_graphics_query_reports_a_bounded_status_without_storing_an_image = function()
    local state = State.new(4, 1)
    local parser = Parser.new(state)
    parser:feed(frame("a=q,i=9,s=1,v=1,f=100,t=d,m=0;" .. png))
    parser:finish()
    Assert.equal(state.kitty_graphics:view().image_count, 0)
    Assert.equal(state:pop_responses()[1], "\27_Gi=9;OK\27\\")
  end,
}
